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
        brand: "#0f62fe",
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    require("@tailwindcss/typography"),
    // vendor/daisyui.js 는 ESM 스타일로 default 를 노출하므로 .default 로 풀어야 합니다.
    require("./vendor/daisyui").default,
    require("./vendor/heroicons"),
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
          "primary": "#0f62fe",
          "primary-content": "#ffffff",
          "secondary": "#161616",
          "secondary-content": "#ffffff",
          "accent": "#0043ce",
          "accent-content": "#ffffff",
          "neutral": "#161616",
          "neutral-content": "#ffffff",
          "base-100": "#ffffff",
          "base-200": "#f4f4f4",
          "base-300": "#e0e0e0",
          "base-content": "#161616",
          "info": "#0f62fe",
          "info-content": "#ffffff",
          "success": "#24a148",
          "success-content": "#ffffff",
          "warning": "#f1c21b",
          "warning-content": "#161616",
          "error": "#da1e28",
          "error-content": "#ffffff",
        },
        dark: {
          "primary": "#0f62fe",
          "primary-content": "#ffffff",
          "secondary": "#ffffff",
          "secondary-content": "#161616",
          "accent": "#4589ff",
          "accent-content": "#161616",
          "neutral": "#262626",
          "neutral-content": "#ffffff",
          "base-100": "#161616",
          "base-200": "#262626",
          "base-300": "#393939",
          "base-content": "#ffffff",
          "info": "#0f62fe",
          "info-content": "#ffffff",
          "success": "#24a148",
          "success-content": "#ffffff",
          "warning": "#f1c21b",
          "warning-content": "#161616",
          "error": "#da1e28",
          "error-content": "#ffffff",
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
