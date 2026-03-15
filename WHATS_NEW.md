# What's new (1.0.5+8 - 2026-03-15)

## Added

- **Premium Quality Chips**: Introduced distinct "LOSSLESS" and "MP3" badges in the player view for immediate quality perception.
- **Dynamic Bitrate Inference**: Autonomous calculation of audio bitrate for online streams (Tidal, Spotify) using downloaded manifest data and track duration.

## New Features

- **Hardware-Grade Metadata Consistency**: Universal display of technical details (Format • Bitrate • Sample Rate • File Size) across All Library tabs, Folders, Albums, and Home Page sections.

## Fixed

- **Trending Songs Metadata**: Resolved an issue where Trending tracks from the Home page would display 0 kbps bitrate.
- **Missing Bitrates**: Fixed missing technical information for local files played from the Folders and Albums sections.
- **Asynchronous UI Updating**: Corrected a state mismatch where the player's audio quality footer would show stale metadata during track transitions.
- **Library Layout View**: Fixed issues with switching between **Grid** and **List** views in the Library section to ensure a consistent browsing experience.

## Changed

- **Stationary Library Header**: Pinned the Library title, search bar, and tab chips to the top of the screen for persistent access and professional feel.
- **Optimized Navigation**: Library tabs now switch instantly via tapping, providing a more solid navigation feel compared to legacy swipe gestures.
- **Unified Playback UI**: Standardized all "Play" and "Shuffle" buttons across the entire application to a consistent high-visibility "Solid Blue" design.
- **Optimized Prefetching**: Next-track metadata fetching is now triggered after 5 seconds of active playback to ensure zero impact on initial streaming performance.
- **Technical Metadata Order**: Standardized the display sequence to: Format • Bitrate • Sample Rate • File Size for better readability.

## Removed

- **Swipe Gestures**: Removed left/right swipe gestures for switching between Library tabs to prevent accidental page flips during scrolling.
- **Shadow Effects**: Removed unnecessary button shadows and legacy elevations to align with the clean, modern glassmorphism UI requirements.
- **Legacy Display Labels**: Cleaned up ad-hoc quality labels in favor of the new unified metadata footer system.
