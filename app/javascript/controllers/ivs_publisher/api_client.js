function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
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
    body: JSON.stringify({ role, publish_attempt_id: ctx._publishAttemptId }),
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
  url.searchParams.set("publish_attempt_id", ctx._publishAttemptId || "")

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

  const attemptId = ctx._publishAttemptId
  for (let retry = 0; retry < 15; retry += 1) {
    if (ctx._publishAttemptId !== attemptId || ctx._publishCancelled) throw new Error("配信開始は取り消されました")
    const resp = await fetch(ctx.startBroadcastUrlValue, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken(),
      },
      body: JSON.stringify({ publish_attempt_id: attemptId }),
    })
    if (resp.ok) return
    const body = await resp.json().catch(() => ({}))
    if ((resp.status === 409 && body.retryable) || resp.status === 503) {
      await new Promise(resolve => setTimeout(resolve, 1000))
      continue
    }
    throw new Error(body.error || `start_broadcast_failed(${resp.status})`)
  }
  throw new Error("配信開始を確認できません。接続を終了してから再試行してください")
}

export async function cancelPublish(ctx, attemptId = ctx._publishAttemptId) {
  if (!attemptId || !ctx.cancelPublishUrlValue) return
  const response = await fetch(ctx.cancelPublishUrlValue, {
    method: "POST", credentials: "same-origin", keepalive: true,
    headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
    body: JSON.stringify({ publish_attempt_id: attemptId }),
  })
  if (!response.ok && response.status !== 404) throw new Error("接続終了を確認できません。再試行してください")
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
      "Accept": "application/json",
      "Content-Type": "application/json",
      "X-CSRF-Token": csrfToken(),
    },
    body: JSON.stringify({ publish_attempt_id: ctx._publishAttemptId }),
  })

  const body = await resp.json()
  if (!resp.ok) throw new Error(body.error || `finish_failed(${resp.status})`)
  return body.redirect_url
}
