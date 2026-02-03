# SlothyTerminal Landing Page UI Guidelines

## Brand Identity

**Tagline:** "Take it slow, ship it fast."

**Tone:** Warm, friendly, approachable

**Visual Style:**
- Warm, cozy, slightly retro aesthetic
- Hand-drawn/illustrated feel matching the app icon
- The sloth character with coffee represents relaxed productivity
- Retro terminal vibes with orange CRT glow

## Color Palette

### Light Mode

| Role | Color | Hex | Usage |
|------|-------|-----|-------|
| Background | Warm Cream | `#F5EDE0` | Page background |
| Surface | Light Tan | `#E8DCC8` | Cards, sections |
| Primary | Terminal Orange | `#E87A3D` | CTAs, links, accents |
| Text Primary | Deep Brown | `#5A4232` | Headings, body text |
| Text Secondary | Medium Brown | `#8B6B4A` | Captions, muted text |
| Accent | Rosy | `#D4A088` | Subtle highlights |

### Dark Mode (Default)

| Role | Color | Hex | Usage |
|------|-------|-----|-------|
| Background | Dark Brown | `#1C1612` | Page background |
| Surface | Warm Dark | `#2A2118` | Cards, sections |
| Primary | Terminal Orange | `#F28C38` | CTAs, links, accents |
| Text Primary | Cream | `#F5EDE0` | Headings, body text |
| Text Secondary | Tan | `#B8A089` | Captions, muted text |
| Accent | Rosy | `#D4A088` | Subtle highlights |

## Typography

**Headings:** System font stack with rounded, friendly feel
```css
font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
```

**Code/Terminal:** Monospace for technical elements
```css
font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace;
```

**Scale:**
- Hero title: 3rem (48px)
- Section headings: 2rem (32px)
- Subheadings: 1.25rem (20px)
- Body: 1rem (16px)
- Small/captions: 0.875rem (14px)

## Components

### Buttons

**Primary (Download/CTA):**
- Background: Terminal Orange (`#E87A3D`)
- Text: White or Cream
- Border-radius: 12px
- Padding: 12px 24px
- Hover: Slightly lighter, subtle lift shadow

**Secondary:**
- Background: Transparent
- Border: 2px solid Terminal Orange
- Text: Terminal Orange
- Same radius and padding

### Cards

- Background: Surface color
- Border-radius: 16px
- Padding: 24px
- Subtle shadow in light mode
- Subtle border in dark mode

### Code Blocks

- Background: Slightly darker than surface
- Border-radius: 8px
- Orange terminal prompt (`>_`)
- Monospace font

## Layout

### Page Structure

```
┌─────────────────────────────────────┐
│  Nav: Logo | Features | Download    │  ← sticky, theme toggle
├─────────────────────────────────────┤
│  HERO                               │
│  [App Icon]                         │
│  SlothyTerminal                     │
│  "Take it slow, ship it fast."     │
│  [Download Button]                  │
├─────────────────────────────────────┤
│  FEATURES (3 cards)                 │
│  • Multi-agent support              │
│  • Native macOS                     │
│  • Real-time stats                  │
├─────────────────────────────────────┤
│  APP SCREENSHOT                     │
│  [Screenshot of the app in action]  │
├─────────────────────────────────────┤
│  INSTALLATION                       │
│  Homebrew / Direct download         │
├─────────────────────────────────────┤
│  Footer: GitHub | License           │
└─────────────────────────────────────┘
```

### Spacing

- Section padding: 80px vertical
- Container max-width: 1200px
- Card gap: 24px
- Element spacing: 16px

### Responsive Breakpoints

- Mobile: < 640px
- Tablet: 640px - 1024px
- Desktop: > 1024px

## Mascot Usage

**App Icon:** Located at `docs/assets/SlothyTerminalIcon.jpg`

**Usage Guidelines:**
- Use as hero focal point
- Can appear in favicon (simplified)
- Don't distort or recolor
- Maintain adequate padding around icon

## Animation (Subtle)

- Smooth theme transitions (0.3s)
- Gentle hover effects on buttons and cards
- No aggressive or distracting animations
- Respect `prefers-reduced-motion`

## Accessibility

- Maintain WCAG AA contrast ratios
- Support keyboard navigation
- Respect system color scheme preference
- Provide alt text for images
- Focus states on interactive elements

## Assets Needed

- [x] App icon (`docs/assets/SlothyTerminalIcon.jpg`)
- [ ] App screenshots (light and dark mode)
- [ ] Favicon (derived from app icon)
- [ ] Open Graph image for social sharing
