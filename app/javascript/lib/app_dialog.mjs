// Branded AppDialog when mounted, native browser dialog otherwise, so a missing
// dialog never turns a confirm/alert/prompt into a silent no-op.
export const confirmDialog = async (message, options) =>
  window.AppDialog ? window.AppDialog.confirm(message, options) : window.confirm(message)

export const alertDialog = async (message, options) =>
  window.AppDialog ? window.AppDialog.alert(message, options) : window.alert(message)

export const promptDialog = async (message, options) =>
  window.AppDialog ? window.AppDialog.prompt(message, options) : window.prompt(message, options?.defaultValue ?? "")
