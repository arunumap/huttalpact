import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropzone", "label", "documentType"]

  connect() {
    this.dragCounter = 0
  }

  // Trigger file input when drop zone is clicked
  browse() {
    this.inputTarget.click()
  }

  // Handle file selection via input
  fileSelected() {
    const files = this.inputTarget.files
    if (files.length > 0) {
      this.uploadFiles(files)
    }
  }

  // Drag events
  dragenter(event) {
    event.preventDefault()
    this.dragCounter++
    this.dropzoneTarget.classList.add("border-indigo-500", "bg-indigo-50")
    this.dropzoneTarget.classList.remove("border-gray-300")
  }

  dragleave(event) {
    event.preventDefault()
    this.dragCounter--
    if (this.dragCounter === 0) {
      this.dropzoneTarget.classList.remove("border-indigo-500", "bg-indigo-50")
      this.dropzoneTarget.classList.add("border-gray-300")
    }
  }

  dragover(event) {
    event.preventDefault()
  }

  drop(event) {
    event.preventDefault()
    this.dragCounter = 0
    this.dropzoneTarget.classList.remove("border-indigo-500", "bg-indigo-50")
    this.dropzoneTarget.classList.add("border-gray-300")

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.uploadFiles(files)
    }
  }

  uploadFiles(files) {
    const url = this.element.dataset.uploadUrl
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    Array.from(files).forEach(file => {
      // Validate file type
      const allowedTypes = [
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "text/plain"
      ]
      if (!allowedTypes.includes(file.type)) {
        this.showFlash(`"${file.name}" is not a supported file type. Please upload PDF, DOCX, or TXT files.`, "error")
        return
      }

      // Validate file size (25MB max)
      if (file.size > 25 * 1024 * 1024) {
        this.showFlash(`"${file.name}" is too large. Maximum file size is 25MB.`, "error")
        return
      }

      const formData = new FormData()
      formData.append("file", file)
      if (this.hasDocumentTypeTarget) {
        formData.append("document_type", this.documentTypeTarget.value)
      }

      // Show uploading state
      this.labelTarget.textContent = `Uploading ${file.name}...`
      this.dropzoneTarget.classList.add("opacity-60", "pointer-events-none")

      fetch(url, {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: formData
      })
      .then(response => {
        if (!response.ok) throw new Error("Upload failed")
        return response.text()
      })
      .then(html => {
        Turbo.renderStreamMessage(html)
      })
      .catch(error => {
        this.showFlash(`Failed to upload "${file.name}". Please try again.`, "error")
      })
      .finally(() => {
        this.labelTarget.textContent = "Drop files here or click to browse"
        this.dropzoneTarget.classList.remove("opacity-60", "pointer-events-none")
        this.inputTarget.value = ""
      })
    })
  }

  showFlash(message, type) {
    const flashEl = document.getElementById("document_upload_flash")
    if (flashEl) {
      const bgClass = type === "error" ? "bg-red-50 text-red-700 ring-red-600/10" : "bg-green-50 text-green-700 ring-green-600/10"
      flashEl.innerHTML = `<div class="rounded-md p-3 ${bgClass} ring-1 ring-inset"><p class="text-sm">${message}</p></div>`
      setTimeout(() => { flashEl.innerHTML = "" }, 5000)
    }
  }
}
