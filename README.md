<p align="center">
	<img src="Memeforge/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="128" alt="Memeforge logo">
</p>

<h1 align="center">Memeforge</h1>

<p align="center">An iOS keyboard for searching GIF memes and generating static memes from prompts.</p>

## Setup

Create `Config/LocalSecrets.xcconfig` with the API keys used by the keyboard extension:

```xcconfig
GIPHY_API_KEY = your-giphy-api-key
GEMINI_API_KEY = your-gemini-api-key
```

`Config/Secrets.xcconfig` includes this file automatically, and `Config/LocalSecrets.xcconfig` is ignored by git.

Open `Memeforge.xcodeproj`, build the `Memeforge` scheme, then enable the keyboard in iOS Settings:

```text
General > Keyboard > Keyboards > Memeforge > Allow Full Access
```

Full Access is required so the keyboard extension can call the GIPHY and Gemini APIs.

## Screenshots

| Search: `disappear homer` | Generate: `doge eating onions in the "this is fine" meme template` |
| --- | --- |
| <img src="docs/screenshots/keyboard-search.png" alt="Search tab showing results for disappear homer" width="360"> | <img src="docs/screenshots/keyboard-generate.png" alt="Generate tab showing Doge eating onions in a this is fine meme template" width="360"> |
