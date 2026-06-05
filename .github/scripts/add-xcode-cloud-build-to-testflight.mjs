import { appendFileSync } from "node:fs";
import { sign } from "node:crypto";

const appStoreConnectHost = "https://api.appstoreconnect.apple.com";

const config = {
	keyId: requiredEnv("APP_STORE_CONNECT_KEY_ID"),
	issuerId: requiredEnv("APP_STORE_CONNECT_ISSUER_ID"),
	privateKey: normalizePrivateKey(requiredEnv("APP_STORE_CONNECT_PRIVATE_KEY")),
	workflowId: requiredEnv("ASC_WORKFLOW_ID"),
	betaGroupId: requiredEnv("ASC_BETA_GROUP_ID"),
	commitSha: requiredEnv("COMMIT_SHA"),
	timeoutMinutes: Number(process.env.TIMEOUT_MINUTES ?? "45"),
	pollIntervalSeconds: Number(process.env.POLL_INTERVAL_SECONDS ?? "30"),
};

if (!Number.isFinite(config.timeoutMinutes) || config.timeoutMinutes <= 0) {
	throw new Error("TIMEOUT_MINUTES must be a positive number");
}

if (!Number.isFinite(config.pollIntervalSeconds) || config.pollIntervalSeconds <= 0) {
	throw new Error("POLL_INTERVAL_SECONDS must be a positive number");
}

const timeoutAt = Date.now() + config.timeoutMinutes * 60_000;
const pollIntervalMs = config.pollIntervalSeconds * 1_000;

const buildRun = await waitForBuildRun();
const build = await waitForBuild(buildRun.id);
const readyBuild = await waitForBuildReady(build.id);
await addBuildToBetaGroup(readyBuild.id);
const finalBuild = await waitForBuildReady(readyBuild.id);

const summary = [
	"### TestFlight Internal Distribution",
	"",
	`- Xcode Cloud run: #${buildRun.attributes.number}`,
	`- Commit: ${config.commitSha}`,
	`- App Store Connect build: ${finalBuild.attributes.version}`,
	`- Build ID: ${finalBuild.id}`,
	`- Internal state: ${buildBetaState(finalBuild)}`,
	"",
].join("\n");

if (process.env.GITHUB_STEP_SUMMARY) {
	appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
}

console.log(`Distributed build ${finalBuild.attributes.version} (${finalBuild.id}) to internal TestFlight group ${config.betaGroupId}.`);

async function waitForBuildRun() {
	while (Date.now() < timeoutAt) {
		const response = await appStoreConnect(`/v1/ciWorkflows/${config.workflowId}/buildRuns?limit=50`);
		const run = response.data
			.filter((candidate) => candidate.attributes.sourceCommit?.commitSha === config.commitSha)
			.sort(byCreatedDate)
			.at(-1);

		if (!run) {
			const latest = response.data.at(-1);
			const latestCommit = latest?.attributes.sourceCommit?.commitSha ?? "unknown";
			console.log(`Waiting for Xcode Cloud run for ${config.commitSha}. Latest seen: ${latest?.attributes.number ?? "none"} (${latestCommit}).`);
			await sleep(pollIntervalMs);
			continue;
		}

		const progress = run.attributes.executionProgress;
		const status = run.attributes.completionStatus;
		console.log(`Xcode Cloud run #${run.attributes.number}: ${progress}${status ? ` / ${status}` : ""}.`);

		if (progress === "COMPLETE") {
			if (status !== "SUCCEEDED") {
				throw new Error(`Xcode Cloud run #${run.attributes.number} completed with status ${status ?? "unknown"}`);
			}

			return run;
		}

		await sleep(pollIntervalMs);
	}

	throw new Error(`Timed out waiting for Xcode Cloud run for ${config.commitSha}`);
}

async function waitForBuild(buildRunId) {
	while (Date.now() < timeoutAt) {
		const response = await appStoreConnect(`/v1/ciBuildRuns/${buildRunId}/builds?limit=20`);
		const build = response.data.sort(byUploadedDate).at(-1);

		if (build) {
			console.log(`Found App Store Connect build ${build.attributes.version} (${build.id}).`);
			return build;
		}

		console.log("Waiting for App Store Connect build record.");
		await sleep(pollIntervalMs);
	}

	throw new Error(`Timed out waiting for App Store Connect build for Xcode Cloud run ${buildRunId}`);
}

async function waitForBuildReady(buildId) {
	while (Date.now() < timeoutAt) {
		const build = await readBuild(buildId);
		const processingState = build.attributes.processingState;
		const internalState = buildBetaState(build);

		console.log(`Build ${build.attributes.version}: ${processingState}, internal state ${internalState ?? "unknown"}.`);

		if (internalState === "MISSING_EXPORT_COMPLIANCE") {
			throw new Error("Build is missing export compliance. Check ITSAppUsesNonExemptEncryption in Info.plist.");
		}

		if (processingState === "VALID" && (internalState === "READY_FOR_BETA_TESTING" || internalState === "IN_BETA_TESTING")) {
			return build;
		}

		if (processingState === "FAILED" || processingState === "INVALID") {
			throw new Error(`Build ${build.attributes.version} processing failed with state ${processingState}`);
		}

		await sleep(pollIntervalMs);
	}

	throw new Error(`Timed out waiting for build ${buildId} to become ready for beta testing`);
}

async function addBuildToBetaGroup(buildId) {
	const groupBuilds = await appStoreConnect(`/v1/betaGroups/${config.betaGroupId}/builds?limit=200`);
	if (groupBuilds.data.some((build) => build.id === buildId)) {
		console.log(`Build ${buildId} is already assigned to beta group ${config.betaGroupId}.`);
		return;
	}

	await appStoreConnect(`/v1/builds/${buildId}/relationships/betaGroups`, {
		method: "POST",
		body: JSON.stringify({
			data: [
				{
					type: "betaGroups",
					id: config.betaGroupId,
				},
			],
		}),
	}, [204]);

	console.log(`Assigned build ${buildId} to beta group ${config.betaGroupId}.`);
}

async function readBuild(buildId) {
	const response = await appStoreConnect(`/v1/builds/${buildId}?include=buildBetaDetail`);
	return {
		...response.data,
		included: response.included ?? [],
	};
}

async function appStoreConnect(path, options = {}, okStatuses = [200, 201, 204]) {
	const response = await fetch(`${appStoreConnectHost}${path}`, {
		...options,
		headers: {
			Authorization: `Bearer ${createJwt()}`,
			"Content-Type": "application/json",
			...(options.headers ?? {}),
		},
	});

	const text = await response.text();
	const body = text ? JSON.parse(text) : null;

	if (!okStatuses.includes(response.status)) {
		throw new Error(`App Store Connect ${response.status} for ${path}: ${JSON.stringify(body)}`);
	}

	return body;
}

function createJwt() {
	const now = Math.floor(Date.now() / 1_000);
	const header = base64Url(JSON.stringify({
		alg: "ES256",
		kid: config.keyId,
		typ: "JWT",
	}));
	const payload = base64Url(JSON.stringify({
		iss: config.issuerId,
		iat: now,
		exp: now + 20 * 60,
		aud: "appstoreconnect-v1",
	}));
	const unsignedToken = `${header}.${payload}`;
	const signature = sign("sha256", Buffer.from(unsignedToken), {
		key: config.privateKey,
		dsaEncoding: "ieee-p1363",
	});

	return `${unsignedToken}.${base64Url(signature)}`;
}

function buildBetaState(build) {
	return build.included
		?.find((item) => item.type === "buildBetaDetails" && item.id === build.id)
		?.attributes
		?.internalBuildState;
}

function byCreatedDate(left, right) {
	return Date.parse(left.attributes.createdDate ?? 0) - Date.parse(right.attributes.createdDate ?? 0);
}

function byUploadedDate(left, right) {
	return Date.parse(left.attributes.uploadedDate ?? 0) - Date.parse(right.attributes.uploadedDate ?? 0);
}

function base64Url(value) {
	return Buffer.from(value)
		.toString("base64")
		.replaceAll("+", "-")
		.replaceAll("/", "_")
		.replaceAll("=", "");
}

function normalizePrivateKey(value) {
	return value.replaceAll("\\n", "\n");
}

function requiredEnv(name) {
	const value = process.env[name];
	if (!value) {
		throw new Error(`${name} is required`);
	}
	return value;
}

function sleep(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}
