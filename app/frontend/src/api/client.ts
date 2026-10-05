export type Job = {
  id: string
  file_name: string
  status: 'queued' | 'processing' | 'completed' | 'failed'
  created_at: string
  summary: string
  extracted_text: string
  error: string
}

type ErrorEnvelope = {
  error?: {
    message?: string
  }
}

async function parseResponse<T>(response: Response): Promise<T> {
  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as ErrorEnvelope
    throw new Error(body.error?.message ?? `Request failed with status ${response.status}.`)
  }
  return (await response.json()) as T
}

export async function uploadDocument(file: File): Promise<Job> {
  const form = new FormData()
  form.append('document', file)
  return parseResponse<Job>(
    await fetch('/api/documents', {
      method: 'POST',
      body: form,
    }),
  )
}

export async function getJob(jobId: string): Promise<Job> {
  return parseResponse<Job>(await fetch(`/api/jobs/${encodeURIComponent(jobId)}`))
}

