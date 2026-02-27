import { marked } from "marked"
import DOMPurify from "dompurify"

export function initMarkdownEditor() {
  const textarea = document.getElementById("markdown-editor")
  const preview = document.getElementById("markdown-preview")

  if (!textarea || !preview) return

  function updatePreview() {
    const raw = marked.parse(textarea.value || "")
    // DOMPurify로 XSS 방어 후 안전한 HTML만 렌더링
    preview.innerHTML = DOMPurify.sanitize(raw)
  }

  textarea.addEventListener("input", updatePreview)

  // 초기 렌더링 (edit 페이지에서 기존 본문이 있는 경우)
  updatePreview()
}
