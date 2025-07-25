# MetalCityscape
=======
# MetalCityscape - Clean Project

A 3D wireframe cityscape with interactive floating photo displays, built with Apple's Metal API.

## Features

- **3D City Model**: Loads BusGameMap.obj city model with wireframe rendering
- **Floating Photo Displays**: Interactive photo squares with highlighted borders
- **Click to Zoom**: Click any photo to smoothly zoom to its position
- **Clean UI**: No distracting camera frustum lines - just photos with borders
- **Automatic Loading**: Loads textures from your asset directory

## Project Structure

```
MetalCityscape-Clean/
├── project.yml              # XcodeGen configuration
├── Sources/                  # Swift source files
│   ├── AppDelegate.swift
│   ├── ViewController.swift
│   ├── Renderer.swift
│   └── MatrixUtilities.swift
├── Shaders/                  # Metal shaders
│   └── Shaders.metal
├── Resources/                # Assets and resources
│   ├── Info.plist
│   ├── Base.lproj/
│   │   └── Main.storyboard
│   └── uploads_files_2720101_BusGameMap.obj
└── README.md
```

## Building the Project

### Method 1: Using XcodeGen (Recommended)

1. Install XcodeGen if you haven't already:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   cd MetalCityscape-Clean
   xcodegen generate
   ```

3. Open the generated project:
   ```bash
   open MetalCityscape.xcodeproj
   ```

4. Build and run (⌘+R)

### Method 2: Manual Xcode Project

If you prefer to create the project manually:

1. Create a new macOS App in Xcode
2. Copy all files from `Sources/` to your project
3. Copy all files from `Shaders/` to your project  
4. Copy all files from `Resources/` to your project
5. Make sure to add the .obj file to "Copy Bundle Resources"

## Asset Loading

The app automatically loads:
- **City Model**: `uploads_files_2720101_BusGameMap.obj` from bundle or fallback path
- **Photo Textures**: Various `download (X).jpg` and `images (X).jpg` files from your texture directory

## Key Improvements

- ✅ **Clean Rendering**: Removed camera frustum wireframes
- ✅ **Highlighted Borders**: Added cyan wireframe borders around photos
- ✅ **Proper Organization**: Sources, Shaders, and Resources folders
- ✅ **XcodeGen Support**: Easy project generation and maintenance
- ✅ **Fallback Loading**: Handles missing assets gracefully
- ✅ **Programmatic UI**: No storyboard dependencies - fully programmatic window creation

## Usage

1. **Launch**: Run the app to see the 3D cityscape with floating photos
2. **Interact**: Click on any photo square to zoom in smoothly
3. **Explore**: Photos are randomly positioned throughout the scene

## Customization

- **More Photos**: Update the `photoFiles` array in `loadTextures()`
- **Different Model**: Replace the .obj file in Resources
- **Photo Count**: Modify the loop count in `setupScene()`
- **Colors**: Adjust wireframe colors in the Metal shaders

This clean project structure makes it easy to maintain and extend the Metal cityscape application!

