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
