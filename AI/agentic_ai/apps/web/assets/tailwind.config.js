// 고급 사용법은 Tailwind 설정 가이드를 참조하세요
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin");

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/web_web.ex",
    "../lib/web_web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    require("@tailwindcss/typography"),
    require("./vendor/daisyui"),
    // LiveView 클래스가 적용될 때만 규칙을 추가하도록
    // tailwind 클래스에 LiveView 클래스 접두사를 붙일 수 있습니다, 예:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"]))
  ],
  daisyui: {
    themes: [
      {
        light: {
          "primary": "#18181b",
          "primary-content": "#fafafa",
          "secondary": "#52525b",
          "secondary-content": "#fafafa",
          "accent": "#3f3f46",
          "accent-content": "#fafafa",
          "neutral": "#27272a",
          "neutral-content": "#e4e4e7",
          "base-100": "#ffffff",
          "base-200": "#fafafa",
          "base-300": "#f4f4f5",
          "base-content": "#18181b",
          "info": "#52525b",
          "info-content": "#fafafa",
          "success": "#3f3f46",
          "success-content": "#fafafa",
          "warning": "#52525b",
          "warning-content": "#fafafa",
          "error": "#18181b",
          "error-content": "#fafafa",
        },
        dark: {
          "primary": "#e4e4e7",
          "primary-content": "#18181b",
          "secondary": "#a1a1aa",
          "secondary-content": "#18181b",
          "accent": "#d4d4d8",
          "accent-content": "#18181b",
          "neutral": "#27272a",
          "neutral-content": "#d4d4d8",
          "base-100": "#09090b",
          "base-200": "#18181b",
          "base-300": "#27272a",
          "base-content": "#e4e4e7",
          "info": "#a1a1aa",
          "info-content": "#18181b",
          "success": "#d4d4d8",
          "success-content": "#18181b",
          "warning": "#a1a1aa",
          "warning-content": "#18181b",
          "error": "#e4e4e7",
          "error-content": "#18181b",
        }
      }
    ],
    darkTheme: "dark",
    base: true,
    styled: true,
    utils: true,
    logs: false,
  }
};
