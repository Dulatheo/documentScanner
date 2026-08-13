// Reference only: device-frame chrome used by the Claude Design prototype to preview
// screens inside an iOS-shaped bezel. Not part of the app itself — kept here so
// implementers can see exactly which iOS chrome (status bar, nav bar, glass pills,
// keyboard) the mockups assume. See docs/DESIGN_SPEC.md for the written spec.

function IOSStatusBar({ dark = false, time = '9:41' }) { /* status bar: time + signal/wifi/battery glyphs */ }
function IOSGlassPill({ children, dark = false, style = {} }) { /* liquid-glass blurred pill used for nav bar buttons */ }
function IOSNavBar({ title = 'Title', dark = false, trailingIcon = true }) { /* large-title nav bar with glass back/ellipsis pills */ }
function IOSListRow({ title, detail, icon, chevron = true, isLast = false, dark = false }) { /* 52px grouped-list row */ }
function IOSList({ header, children, dark = false }) { /* inset grouped list container, radius 26 */ }
function IOSDevice({ children, width = 402, height = 874, dark = false, title, keyboard = false }) {
  /* device bezel: dynamic island, status bar, optional nav bar, content, home indicator */
}
function IOSKeyboard({ dark = false }) { /* iOS 26 liquid-glass software keyboard */ }

// Full source preserved in git history of the uploaded design bundle; this stub is kept
// only as a pointer for engineers — build against native SwiftUI, not this JSX.
