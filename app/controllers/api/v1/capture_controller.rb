module Api
  module V1
    # Job queue polled by the IdeaFoundry Chrome extension. Contract mirrors
    # idea-chrome-ext/server/queue.mjs; set the extension's queue address to <app>/api/v1/capture.
    class CaptureController < ActionController::API
      before_action :no_store
      before_action :authenticate_api_key
      before_action :reject_browser_pages
      before_action { CaptureJob.expire_stale! }

      def health
        render json: { ok: true }
      end

      def create
        job = @user.capture_jobs.new(url: params[:url].to_s.strip, file_format: params[:format].presence || "md")
        if job.save
          render json: job.as_extension_json, status: :created
        else
          status = job.errors[:base].include?("Queue is full") ? :too_many_requests : :bad_request
          render json: { error: job.errors.full_messages.to_sentence }, status: status
        end
      end

      def show
        job = find_job or return
        render json: job.as_extension_json
      end

      def claim
        job = CaptureJob.claim_next!(@user)
        job ? render(json: job.as_extension_json) : head(:no_content)
      end

      def complete
        job = find_job or return
        state = params[:state].to_s
        return render(json: { error: "Invalid result state" }, status: :bad_request) unless %w[completed failed].include?(state)
        return render(json: { error: "Job has not been claimed" }, status: :conflict) if job.state == "queued"
        unless job.finished_at
          job.finish!(state: state, filename: params[:filename], error: params[:error])
          Kb::TreeBroadcaster.call(@user) if state == "completed" # the extension just saved a file into the KB
        end
        render json: job.as_extension_json
      end

      private

      def no_store
        response.headers["Cache-Control"] = "no-store"
      end

      def authenticate_api_key
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        api_key = ApiKey.authenticate(token)
        return @user = api_key.user if api_key
        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def reject_browser_pages
        origin = request.headers["Origin"]
        return if origin.blank? || origin.start_with?("chrome-extension://")
        render json: { error: "Browser page requests are not accepted." }, status: :forbidden
      end

      def find_job
        @user.capture_jobs.find_by(public_id: params[:id]) ||
          (render(json: { error: "Job not found" }, status: :not_found) && nil)
      end
    end
  end
end
