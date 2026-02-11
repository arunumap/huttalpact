import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropzone", "input", "label", "fileList", "submitArea", "submitButton", "submitText"]

  connect() {
    this.files = []
  }

  browse() {
    this.inputTarget.click()
  }

  dragenter(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-amber-500", "bg-amber-50/50")
  }

  dragleave(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-amber-500", "bg-amber-50/50")
  }

  dragover(event) {
    event.preventDefault()
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-amber-500", "bg-amber-50/50")

    const droppedFiles = event.dataTransfer.files
    if (droppedFiles.length > 0) {
      this.addFiles(Array.from(droppedFiles))
    }
  }

  fileSelected(event) {
    const selectedFiles = event.target.files
    if (selectedFiles.length > 0) {
      this.addFiles(Array.from(selectedFiles))
    }
  }

  addFiles(newFiles) {
    const allowedTypes = [
      "application/pdf",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "text/plain"
    ]
    const maxSize = 25 * 1024 * 1024 // 25MB

    newFiles.forEach(file => {
      if (!allowedTypes.includes(file.type)) {
        alert(`"${file.name}" is not a supported file type. Please upload PDF, DOCX, or TXT files.`)
        return
      }

      if (file.size > maxSize) {
        alert(`"${file.name}" is too large. Maximum size is 25MB.`)
        return
      }

      // Avoid duplicates by name+size
      const isDuplicate = this.files.some(f => f.name === file.name && f.size === file.size)
      if (isDuplicate) return

      this.files.push(file)
    })

    this.syncInputFiles()
    this.renderFileList()
    this.updateSubmitArea()
  }

  removeFile(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.files.splice(index, 1)
    this.syncInputFiles()
    this.renderFileList()
    this.updateSubmitArea()
  }

  syncInputFiles() {
    const dataTransfer = new DataTransfer()
    this.files.forEach(f => dataTransfer.items.add(f))
    this.inputTarget.files = dataTransfer.files
  }

  updateSubmitArea() {
    if (this.files.length > 0) {
      this.submitAreaTarget.classList.remove("hidden")
      const fileWord = this.files.length === 1 ? "file" : "files"
      this.submitTextTarget.textContent = `Upload ${this.files.length} ${fileWord} & Extract with AI`
    } else {
      this.submitAreaTarget.classList.add("hidden")
    }
  }

  renderFileList() {
    if (this.files.length === 0) {
      this.fileListTarget.classList.add("hidden")
      this.fileListTarget.innerHTML = ""
      this.labelTarget.textContent = "Drop your contract files here or click to browse"
      return
    }

    this.fileListTarget.classList.remove("hidden")
    this.labelTarget.textContent = `${this.files.length} file${this.files.length === 1 ? "" : "s"} selected — drop more or click to add`

    this.fileListTarget.innerHTML = this.files.map((file, index) => `
      <div class="flex items-center gap-3 rounded-lg bg-white px-4 py-3 ring-1 ring-gray-200">
        <svg class="h-8 w-8 text-amber-500 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
        </svg>
        <div class="min-w-0 flex-1">
          <p class="text-sm font-medium text-gray-900 truncate">${file.name}</p>
          <p class="text-xs text-gray-500">${this.formatFileSize(file.size)}</p>
        </div>
        <button type="button" data-action="click->draft-upload#removeFile" data-index="${index}" class="text-gray-400 hover:text-red-500">
          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `).join("")
  }

  formatFileSize(bytes) {
    if (bytes === 0) return "0 Bytes"
    const k = 1024
    const sizes = ["Bytes", "KB", "MB", "GB"]
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i]
  }
}
