module Api
  module V1
    class IdeaDocumentsController < ActionController::API
      before_action :authenticate_idea_agent_token
      before_action :ensure_token_matches_idea

      def show
        render json: serialize_document
      end

      def update
        return if reject_stale_base_version

        operation = document_operation
        unless operation
          render json: { error: "Provide exactly one of description, content, or append" }, status: :unprocessable_content
          return
        end

        next_description = next_document_text(operation)
        if next_description == current_document_text
          render json: serialize_document.merge(changed: false)
          return
        end

        @idea.transaction do
          @idea.description = next_description
          @idea.save!
          @idea.create_version(agent_commit_message(operation))
        end

        render json: serialize_document.merge(changed: true, version_id: @idea.latest_version&.id)
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      end

      private

      def authenticate_idea_agent_token
        @idea_agent_token = IdeaAgentToken.authenticate(bearer_token)
        return if @idea_agent_token

        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def ensure_token_matches_idea
        @idea = @idea_agent_token.idea
        return if @idea.id.to_s == params[:idea_id].to_s

        render json: { error: "Not found" }, status: :not_found
      end

      def bearer_token
        request.headers["Authorization"].to_s[/\ABearer\s+(.+)\z/, 1]
      end

      def serialize_document
        {
          idea_id: @idea.id,
          title: @idea.title,
          description: current_document_text,
          updated_at: @idea.updated_at,
          latest_version_id: @idea.latest_version&.id
        }
      end

      def document_operation
        keys = %w[description content append].select { |key| params.key?(key) }
        return unless keys.one?

        key = keys.first
        value = params[key]
        return if value.nil?
        return if key == "append" && value.to_s.blank?

        [key, value.to_s]
      end

      def next_document_text(operation)
        key, value = operation
        return [current_document_text.presence, value.strip].compact.join("\n\n") if key == "append"

        value
      end

      def current_document_text
        @idea.description.to_plain_text.to_s
      end

      def reject_stale_base_version
        return false if params[:base_version_id].blank?

        latest_version_id = @idea.latest_version&.id
        return false if latest_version_id.to_s == params[:base_version_id].to_s

        render json: serialize_document.merge(
          error: "Base version is stale",
          latest_version_id: latest_version_id
        ), status: :conflict
        true
      end

      def agent_commit_message(operation)
        action = operation.first == "append" ? "Appended to document" : "Updated document"
        message = params[:commit_message].presence || action

        "#{@idea_agent_token.name}: #{message}"
      end
    end
  end
end
