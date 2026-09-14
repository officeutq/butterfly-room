function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

async function publisherJson(url, method, params) {
  if (method === "GET") {
    url = new URL(url, window.location.origin)
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value))
  }
  const resp = await fetch(url, {
    method, credentials: "same-origin",
    headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
    ...(method === "GET" ? {} : { body: JSON.stringify(params) }),
  })
  const body = await resp.json()
  if (!resp.ok || (body.error && !body.state)) {
    const error = new Error(body.message || "配信操作を完了できませんでした。再確認してください。")
    error.status = resp.status
    error.code = body.error
    throw error
  }
  return body
}

export function issuePublisherToken(ctx, attempt) {
  return publisherJson(ctx.tokenUrlValue, "POST", {
    role: "publisher", request_id: attempt.requestId, expected_generation: attempt.expectedGeneration,
  })
}

export function confirmPublisher(ctx, attempt) {
  return publisherJson(ctx.startBroadcastUrlValue, "PATCH", { request_id: attempt.requestId, generation: attempt.generation })
}

export function readPublisherState(ctx, attempt) {
  return publisherJson(ctx.publisherStateUrlValue, "GET", { request_id: attempt.requestId })
}

export function cancelPublisher(ctx, attempt) {
  return publisherJson(ctx.cancelBroadcastUrlValue, "POST", { request_id: attempt.requestId, generation: attempt.generation })
}

export function changePublisherStatus(ctx, attempt, to) {
  return publisherJson(ctx.statusUrlValue, "PATCH", {
    stream_session_id: ctx.streamSessionIdValue, request_id: attempt.requestId, generation: attempt.generation, to,
  })
}

export function finishPublisher(ctx, request) {
  return publisherJson(ctx.finishUrlValue, "POST", request)
}

export function retryPublisherDisconnect(ctx) {
  return publisherJson(ctx.retryPublisherDisconnectUrlValue, "POST", {})
}

export async function fetchParticipantToken(ctx, role) {
  const resp = await fetch(ctx.tokenUrlValue, {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": csrfToken(),
    },
    body: JSON.stringify({ role }),
  })

  let body = null
  try {
    body = await resp.json()
  } catch (_) {}

  if (!resp.ok) {
    throw new Error(`token_api_failed(${resp.status}) ${body?.error || ""}`.trim())
  }

  return body.participant_token
}

export async function patchBoothStatus(ctx, to) {
  console.log("[ivs-publisher] statusUrlValue=", ctx.statusUrlValue, "to=", to)
  if (!ctx.statusUrlValue) return

  const url = new URL(ctx.statusUrlValue, window.location.origin)
  url.searchParams.set("to", to)
  if (ctx.publisherControlValue) {
    url.searchParams.set("stream_session_id", ctx.streamSessionIdValue)
    url.searchParams.set("request_id", ctx._publisherAttempt?.requestId || "")
    url.searchParams.set("generation", ctx._publisherAttempt?.generation ?? "")
  }

  const resp = await fetch(url.toString(), {
    method: "PATCH",
    redirect: "manual",
    credentials: "same-origin",
    headers: {
      "Accept": "text/vnd.turbo-stream.html",
      "X-CSRF-Token": csrfToken(),
    },
  })

  if (resp.status >= 300 && resp.status < 400) {
    return
  }

  if (!resp.ok) throw new Error(`booth_status_failed(${resp.status})`)

  const html = await resp.text()
  if (html && window.Turbo?.renderStreamMessage) {
    window.Turbo.renderStreamMessage(html)
  }
}

export async function patchBroadcastStartedAt(ctx) {
  if (!ctx.hasStartBroadcastUrlValue) return

  const resp = await fetch(ctx.startBroadcastUrlValue, {
    method: "PATCH",
    credentials: "same-origin",
    headers: {
      "Accept": "application/json",
      "X-CSRF-Token": csrfToken(),
    },
  })

  if (!resp.ok) {
    throw new Error(`start_broadcast_failed(${resp.status})`)
  }
}

export async function reloadMetaDisplay(ctx) {
  if (!ctx.hasMetaDisplayUrlValue) return

  const frame = document.getElementById("stream_meta_display")
  if (!frame) return

  const currentSrc = frame.getAttribute("src")
  if (currentSrc === ctx.metaDisplayUrlValue) {
    if (typeof frame.reload === "function") {
      await frame.reload()
    } else {
      frame.removeAttribute("src")
      frame.setAttribute("src", ctx.metaDisplayUrlValue)
    }
    return
  }

  frame.setAttribute("src", ctx.metaDisplayUrlValue)
}

export async function postFinish(ctx) {
  const resp = await fetch(ctx.finishUrlValue, {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "Accept": "text/html, application/xhtml+xml",
      "X-CSRF-Token": csrfToken(),
    },
  })

  if (!resp.ok) throw new Error(`finish_failed(${resp.status})`)

  return resp.url
}
