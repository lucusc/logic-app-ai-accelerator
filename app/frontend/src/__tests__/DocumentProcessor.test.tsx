import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, expect, test, vi } from 'vitest'
import { DocumentProcessor } from '../components/DocumentProcessor'

afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
})

test('renders the document upload experience', () => {
  render(<DocumentProcessor />)
  expect(screen.getByRole('heading', { name: /logic app ai document processing/i })).toBeVisible()
  expect(screen.getByLabelText(/pdf document/i)).toBeVisible()
})

test('uploads a selected PDF and displays queued status', async () => {
  vi.spyOn(globalThis, 'fetch').mockResolvedValue(
    new Response(
      JSON.stringify({
        id: 'job-1',
        file_name: 'sample.pdf',
        status: 'queued',
        created_at: '2026-01-01T00:00:00Z',
        summary: '',
        extracted_text: '',
        error: '',
      }),
      { status: 202, headers: { 'Content-Type': 'application/json' } },
    ),
  )
  render(<DocumentProcessor />)

  const file = new File(['pdf'], 'sample.pdf', { type: 'application/pdf' })
  await userEvent.upload(screen.getByLabelText(/pdf document/i), file)
  await userEvent.click(screen.getByRole('button', { name: /upload and process/i }))

  expect(await screen.findByText('queued')).toBeVisible()
})

test('shows a validation error when no document is selected', async () => {
  render(<DocumentProcessor />)
  await userEvent.click(screen.getByRole('button', { name: /upload and process/i }))
  expect(screen.getByRole('alert')).toHaveTextContent(/choose a pdf/i)
})
