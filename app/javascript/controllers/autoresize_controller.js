import { Controller } from "@hotwired/stimulus"

// Grows the textarea to fit content as the user types. Capped at 20 rows.
export default class extends Controller {
  connect() { this.resize() }
  resize() {
    this.element.style.height = "auto"
    const cap = parseFloat(getComputedStyle(this.element).lineHeight) * 20
    this.element.style.height = Math.min(this.element.scrollHeight, cap) + "px"
  }
}
