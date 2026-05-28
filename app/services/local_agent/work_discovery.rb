module LocalAgent
  class WorkDiscovery
    RECENT_EVENT_WINDOW = 1.hour

    def initialize(user)
      @user = user
    end

    def list(limit: 25)
      candidates = []
      candidates.concat(question_candidates)
      candidates.concat(submission_candidates)
      candidates.concat(idea_candidates)
      candidates.concat(todo_candidates)
      candidates.concat(build_item_candidates)
      candidates.concat(attachment_candidates)
      candidates.concat(organization_candidates)
      candidates.concat(github_candidates)

      candidates
        .map { |candidate| penalize_recent_activity(candidate) }
        .sort_by { |candidate| [-candidate[:priority], candidate[:target_type], candidate[:target_id].to_i] }
        .first(limit)
    end

    private

    attr_reader :user

    def question_candidates
      answered_question_ids =
        user.agent_events
            .where(event_type: "answer", target_type: "AgentEvent")
            .where.not(target_id: nil)
            .select(:target_id)

      user.agent_events
          .where(event_type: "question")
          .where.not(id: answered_question_ids)
          .recent
          .limit(10)
          .map do |question|
        candidate(question, 95, "Answer user question to the local agent", {
          question: question.payload&.dig("question").presence || question.summary,
          asked_at: question.created_at,
          context_record: {
            record_type: "User",
            record_id: user.id
          },
          response_instructions: "Read the User context record before answering. Record the answer with record_event event_type=answer, target_type=AgentEvent, target_id=#{question.id}. Put the answer in summary and payload.answer."
        })
      end
    end

    def submission_candidates
      user.submissions.pending.recent.limit(20).map do |submission|
        priority = 80
        priority += 20 if submission.high?
        priority += 10 if submission.created_at < 7.days.ago

        candidate(submission, priority, "Review pending submission", {
          title: submission.title,
          priority: submission.priority,
          temporary_idea_id: submission.temporary_idea_id
        })
      end
    end

    def idea_candidates
      candidates = []
      user.ideas.active.includes(:todo_items).order(updated_at: :asc).limit(50).each do |idea|
        description = idea.description.to_plain_text.to_s.strip
        if description.blank? || description.length < 80
          candidates << candidate(idea, 70, "Improve weak idea description", {
            title: idea.title,
            description_length: description.length,
            state: idea.state
          })
        end

        if idea.todo_items.pending.none? && !idea.rejected? && !idea.shipped?
          candidates << candidate(idea, 65, "Create a next todo for active idea", {
            title: idea.title,
            state: idea.state
          })
        end

        if idea.cool_off_expired?
          candidates << candidate(idea, 75, "Cool-off timer expired", {
            title: idea.title,
            state: idea.state,
            cool_off_until: idea.cool_off_until
          })
        end

        if idea.metadata&.dig("enrichment_error").present?
          candidates << candidate(idea, 55, "Resolve stale enrichment error", {
            title: idea.title,
            error: idea.metadata["enrichment_error"]
          })
        end
      end
      candidates
    end

    def todo_candidates
      TodoItem.joins(:idea)
              .where(ideas: { user_id: user.id })
              .where(completed: false)
              .order(updated_at: :asc)
              .limit(20)
              .map do |todo|
        candidate(todo, 45, "Elaborate or group pending todo", {
          title: todo.title,
          idea_id: todo.idea_id
        })
      end
    end

    def build_item_candidates
      user.build_items.pending.order(updated_at: :asc).limit(20).filter_map do |item|
        reason =
          if item.description.blank?
            "Add build item detail"
          elsif item.checklist_remaining_count.positive?
            "Refine incomplete build checklist"
          end
        next unless reason

        candidate(item, 50, reason, {
          title: item.title,
          checklist_remaining_count: item.checklist_remaining_count
        })
      end
    end

    def attachment_candidates
      user.ideas.active.limit(50).filter_map do |idea|
        next if idea.ocr_attachment_parts.blank?
        next if idea.notes.where("body LIKE ?", "%OCR%").exists?

        candidate(idea, 60, "Summarize OCR attachment text into notes", {
          title: idea.title,
          ocr_part_count: idea.ocr_attachment_parts.size
        })
      end
    end

    def organization_candidates
      candidates = []
      user.lists.named.left_outer_joins(:idea_lists).group("lists.id").having("COUNT(idea_lists.id) = 0").limit(10).each do |list|
        candidates << candidate(list, 35, "Review underused list", { name: list.name })
      end

      user.topologies.left_outer_joins(:idea_topologies).group("topologies.id").having("COUNT(idea_topologies.id) = 0").limit(10).each do |topology|
        candidates << candidate(topology, 35, "Review underused topology", { name: topology.name, full_path: topology.full_path })
      end

      candidates
    end

    def github_candidates
      return [] unless user.github_configured?

      GithubRepository.joins(:idea)
                      .where(ideas: { user_id: user.id })
                      .where("github_repositories.last_checked_at IS NULL OR github_repositories.last_checked_at < ?", 1.day.ago)
                      .limit(10)
                      .map do |repository|
        candidate(repository.idea, 40, "Refresh GitHub repository tracking", {
          title: repository.idea.title,
          repository_url: repository.repository_url,
          last_checked_at: repository.last_checked_at
        })
      end
    end

    def candidate(record, priority, reason, payload)
      {
        priority: priority,
        target_type: record.class.name,
        target_id: record.id,
        reason: reason,
        payload: payload
      }
    end

    def penalize_recent_activity(candidate)
      return candidate unless recent_event_for?(candidate[:target_type], candidate[:target_id])

      candidate.merge(priority: candidate[:priority] - 20, recently_touched: true)
    end

    def recent_event_for?(target_type, target_id)
      user.agent_events
          .where(target_type: target_type, target_id: target_id)
          .where("created_at >= ?", RECENT_EVENT_WINDOW.ago)
          .exists?
    end
  end
end
