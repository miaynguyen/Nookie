# Chloe Li — Character Artwork and Room Background Contributions

I created the whole decoration part and imprived the UX flow of the Nookie. Including all of the character artwork and room background artwork for Nookie. This folder documents those visual contributions, links to assets already included in the shared project, and archives additional original artwork.

## Contribution scope
- Created and in charge of the part:[CharacterCustomization.swift](../../CharacterCustomization.swift) 
- Character artwork: a base model, two default character illustrations, and separate hair, top, bottom, and shoe images.
- Room backgrounds: Sky Blue, Blush Pink, Vintage, and Gaming.
- Additional original artwork: 10 bags, six headphones, two room illustrations, and one character illustration.
- [Character artwork inventory and previews](Character-Artwork.md)
- [Room background inventory and previews](Room-Backgrounds.md)
- [Original artwork archive and previews](Source-Artwork.md)
- [Source-to-repository manifest for all 65 original PNGs](Artwork-Manifest.json)
- Improved the onboarding flow and the whole UX flow

## Existing assets and duplicate check

The repository already contains 42 character PNGs and four room PNGs. All 46 files were compared using SHA-256 with both local project copies inspected for this contribution record; every file matched byte for byte.

The contributor's original `Charactor Assets` folder contains 65 PNGs. Of these, 42 character files are byte-identical to existing repository images. Four room files have the same dimensions and premultiplied RGBA pixels as the existing backgrounds, despite different PNG bytes. Those 46 images are referenced at their existing locations. The remaining 19 original PNGs are archived under `Assets/`, preserving their filenames and bytes.

These archived images are not integrated into the current app yet. This change adds artwork documentation and source assets without copying the Xcode project or replacing application files.

The shared [CharacterCustomization.swift](../../CharacterCustomization.swift) already contains the character layering, customization categories, room choices, and room scene composition.
