import { FormEvent, useEffect, useRef, useState } from 'react'
import { getJob, Job, uploadDocument } from '../api/client'

const terminalStatuses = new Set<Job['status']>(['completed', 'failed'])

export function DocumentProcessor() {
  const [file, setFile] = useState<File | null>(null)
  const [job, setJob] = useState<Job | null>(null)
  const [error, setError] = useState('')
  const [uploading, setUploading] = useState(false)
  const pollingRef = useRef<number | null>(null)

  useEffect(() => {
    if (!job || terminalStatuses.has(job.status)) {
      return
    }
    pollingRef.current = window.setInterval(async () => {
      try {
        const updated = await getJob(job.id)
        setJob(updated)
      } catch (pollError) {
        setError(pollError instanceof Error ? pollError.message : 'Unable to refresh the job.')
      }
    }, 2000)
    return () => {
      if (pollingRef.current !== null) {
        window.clearInterval(pollingRef.current)
      }
    }
  }, [job])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!file) {
      setError('Choose a PDF document before submitting.')
      return
    }
    setError('')
    setUploading(true)
    try {
      setJob(await uploadDocument(file))
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : 'The upload failed.')
    } finally {
      setUploading(false)
    }
  }

  return (
    <main>
      <section className="hero" aria-labelledby="page-title">
        <p className="eyebrow">Azure solution accelerator</p>
        <h1 id="page-title">Logic App AI document processing</h1>
        <p>
          Upload a PDF. Logic Apps orchestrates Document Intelligence, Microsoft Foundry,
          Azure AI Search, Storage, and Cosmos DB.
        </p>
      </section>

      <section className="panel" aria-labelledby="upload-title">
        <h2 id="upload-title">Process a document</h2>
        <form onSubmit={submit}>
          <label htmlFor="document">PDF document</label>
          <input
            id="document"
            name="document"
            type="file"
            accept="application/pdf,.pdf"
            onChange={(event) => setFile(event.target.files?.[0] ?? null)}
          />
          <button type="submit" disabled={uploading}>
            {uploading ? 'Uploading…' : 'Upload and process'}
          </button>
        </form>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
      </section>

      {job && (
        <section className="panel result" aria-live="polite" aria-labelledby="result-title">
          <h2 id="result-title">Processing result</h2>
          <dl>
            <div>
              <dt>Status</dt>
              <dd>{job.status}</dd>
            </div>
            <div>
              <dt>Document</dt>
              <dd>{job.file_name}</dd>
            </div>
          </dl>
          {job.summary && (
            <>
              <h3>Summary</h3>
              <p>{job.summary}</p>
            </>
          )}
        </section>
      )}
    </main>
  )
}

