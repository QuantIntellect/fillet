import CoreFoundation

// Private CoreGraphics / SkyLight calls for managing WindowServer spaces.
//
// Fillet creates its own space, pins it above every normal Space with an absolute level, and puts its
// corner windows in it. Windows in ordinary Spaces (even "all Spaces" overlays) are moved along with
// Space-switch and full-screen animations and vanish for a moment; windows in this space stay put.
// The same technique is used by boring.notch (boringNotch/private/CGSSpace.swift, from avaidyam/Parrot).
//
// These symbols are undocumented and could change in a future macOS release.

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
func _CGSDefaultConnection() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
func CGSSpaceCreate(_ cid: CGSConnectionID, _ flag: Int, _ options: CFDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceDestroy")
func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)

@_silgen_name("CGSSpaceSetAbsoluteLevel")
func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)

@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSShowSpaces")
func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)

@_silgen_name("CGSHideSpaces")
func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)
