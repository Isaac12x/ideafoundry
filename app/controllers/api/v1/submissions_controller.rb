module Api
  module V1
    class SubmissionsController < ActionController::API
      before_action :authenticate_api_key

      def create
        result = IntakeSubmissionService.new(
          user: @user,
          title: params[:title],
          body: params[:body],
          source: params[:source],
          source_reference: params[:source_reference],
          priority: params[:priority],
          raw_payload: parse_raw_data,
          attachments: normalized_files,
          temporary_idea_id: temporary_idea_id_param
        ).call

        render json: serialize_submission(result.submission, action: result.action, target: result.target_type),
               status: result.created? ? :created : :ok
      rescue ActiveRecord::RecordNotUnique
        render json: { error: "Duplicate submission (source + source_reference already exists)" }, status: :conflict
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Temporary idea id not found" }, status: :not_found
      end

      def show
        submission = find_submission!(params[:id])
        render json: serialize_submission(submission)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      private

      def authenticate_api_key
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        api_key = ApiKey.authenticate(token)

        if api_key
          @user = api_key.user
        else
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def parse_raw_data
        sanitize_raw_data(JSON.parse(request.raw_post))
      rescue JSON::ParserError
        request.raw_post
      end

      def temporary_idea_id_param
        params[:temporary_idea_id].presence || params[:idea_reference].presence || params[:intake_reference].presence
      end

      def normalized_files
        Array(params[:files]).filter_map do |file_data|
          payload = if file_data.respond_to?(:to_unsafe_h)
                      file_data.to_unsafe_h.with_indifferent_access
                    else
                      file_data.to_h.with_indifferent_access
                    end

          next if payload[:filename].blank? || payload[:data].blank?

          {
            io: StringIO.new(Base64.decode64(payload[:data])),
            filename: payload[:filename],
            content_type: payload[:content_type] || "application/octet-stream"
          }
        end
      end

      def find_submission!(identifier)
        if identifier.to_s.match?(/\A\d+\z/)
          @user.submissions.find_by(id: identifier) || @user.submissions.find_by_reference!(identifier)
        else
          @user.submissions.find_by_reference!(identifier)
        end
      end

      def serialize_submission(submission, action: nil, target: nil)
        {
          id: submission.id,
          temporary_idea_id: submission.temporary_idea_id,
          action: action,
          target: target,
          status: submission.status,
          idea_id: submission.idea_id,
          reviewed_at: submission.reviewed_at,
          created_at: submission.created_at,
          updated_at: submission.updated_at
        }.compact
      end

      def sanitize_raw_data(value)
        case value
        when Array
          value.map { |item| sanitize_raw_data(item) }
        when Hash
          value.each_with_object({}) do |(key, item), sanitized|
            sanitized[key] = key.to_s == "data" ? "[base64 omitted]" : sanitize_raw_data(item)
          end
        else
          value
        end
      end
    end
  end
end
