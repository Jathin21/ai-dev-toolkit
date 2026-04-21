import { Controller } from "@hotwired/stimulus"

// Usage: <button data-controller="clipboard"
//                data-clipboard-source-value="#generated-sql"
//                data-action="click->clipboard#copy">Copy SQL</button>
export default class extends Controller {
  static values = { source: String }

  async copy() {
    const el = document.querySelector(this.sourceValue)
    if (!el) return
    await navigator.clipboard.writeText(el.innerText)
    const original = this.element.innerText
    this.element.innerText = "Copied!"
    setTimeout(() => (this.element.innerText = original), 1500)
  }
}
