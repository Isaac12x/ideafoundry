# FluidVoice is the general voice-message adapter. It uses the bundled local
# transcription service by default and can be pointed at a dedicated
# FluidVoice-compatible /transcribe endpoint without changing the KB job flow.
class FluidVoiceClient
  Error = LocalVoiceIdClient::Error

  def self.transcribe(audio:, filename:, content_type:)
    base_url = ServiceSettings.fetch("FLUIDVOICE_SERVICE_URL") ||
               ServiceSettings.fetch("VOICE_ID_SERVICE_URL", LocalVoiceIdClient::DEFAULT_URL)
    LocalVoiceIdClient.new(base_url: base_url).transcribe(
      audio: audio,
      filename: filename,
      content_type: content_type
    )
  end
end
