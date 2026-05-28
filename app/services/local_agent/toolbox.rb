module LocalAgent
  class Toolbox
    MUTATING_TOOLS = %w[
      update_idea create_note create_todo update_todo update_build_item
      approve_submission reject_submission transition_idea assign_list
      assign_topology create_fact create_maxim run_enrichment
      create_recommendation record_event
    ].freeze

    READ_TOOLS = %w[get_settings list_work read_record].freeze
    TERMINAL_IDEA_STATES = %w[rejected shipped].freeze
    TOOL_DESCRIPTIONS = {
      "get_settings" => "Read current Rails local-agent settings and status.",
      "list_work" => "List prioritized Idea Foundry work candidates.",
      "read_record" => "Read fresh context for an Idea Foundry record.",
      "update_idea" => "Constructively update an idea through Rails history hooks.",
      "create_note" => "Create a note for an idea.",
      "create_todo" => "Create a todo item for an idea.",
      "update_todo" => "Update a todo item through Rails validation.",
      "update_build_item" => "Update a build item through Rails validation.",
      "approve_submission" => "Approve a submission when Rails policy allows it.",
      "reject_submission" => "Reject a submission, or create a recommendation if destructive actions are disabled.",
      "transition_idea" => "Transition an idea lifecycle state through Rails policy.",
      "assign_list" => "Assign an idea to an Idea Foundry list.",
      "assign_topology" => "Assign an idea to an Idea Foundry topology.",
      "create_fact" => "Create a knowledge-base fact.",
      "create_maxim" => "Create a knowledge-base maxim.",
      "run_enrichment" => "Request Rails enrichment for an idea.",
      "create_recommendation" => "Create a reviewable AgentRecommendation.",
      "record_event" => "Record an AgentEvent summary, heartbeat, skip, recommendation, error, or action."
    }.freeze

    def self.supported_tool_names
      (READ_TOOLS + MUTATING_TOOLS).freeze
    end

    def self.tool_definitions
      supported_tool_names.map do |name|
        {
          name: name,
          kind: READ_TOOLS.include?(name) ? "read" : "write",
          description: TOOL_DESCRIPTIONS.fetch(name)
        }
      end
    end

    def initialize(user:, agent_run: nil, review_override: false)
      @user = user
      @agent_run = agent_run
      @review_override = review_override
    end

    def call(tool_name, arguments = {})
      tool = tool_name.to_s
      args = normalize_arguments(arguments)

      return error("unknown_tool", "Unknown local agent tool: #{tool}") unless supported_tool?(tool)
      return disabled_error if MUTATING_TOOLS.include?(tool) && !local_agent_enabled?

      send("tool_#{tool}", args)
    rescue ActiveRecord::RecordNotFound => e
      error("not_found", e.message)
    rescue ActiveRecord::RecordInvalid => e
      error("validation_failed", e.record.errors.full_messages)
    rescue ArgumentError => e
      error("invalid_arguments", e.message)
    end

    private

    attr_reader :user, :agent_run

    def supported_tool?(tool)
      self.class.supported_tool_names.include?(tool)
    end

    def local_agent_enabled?
      @review_override || user.local_agent_enabled?
    end

    def destructive_actions_enabled?
      @review_override || user.local_agent_destructive_actions_enabled?
    end

    def disabled_error
      error("local_agent_disabled", "Local agent writes are disabled.")
    end

    def ok(payload = {})
      { ok: true }.merge(payload)
    end

    def error(code, details)
      { ok: false, error: code, details: details }
    end

    def normalize_arguments(arguments)
      raw = if arguments.respond_to?(:to_unsafe_h)
              arguments.to_unsafe_h
            elsif arguments.respond_to?(:to_h)
              arguments.to_h
            else
              {}
            end

      raw.deep_stringify_keys
    end

    def tool_get_settings(_args)
      ok(settings: user.local_agent_settings, status: user.local_agent_status)
    end

    def tool_list_work(args = {})
      limit = (args["limit"].presence || 25).to_i
      limit = 25 unless limit.positive?
      work = LocalAgent::WorkDiscovery.new(user).list(limit: limit)
      ok(work: work)
    end

    def tool_read_record(args)
      record = find_target!(
        args["target_type"].presence || args["record_type"],
        args["target_id"].presence || args["record_id"] || args["id"]
      )
      ok(record: serialize_record(record))
    end

    def tool_update_idea(args)
      idea = user.ideas.find(args.fetch("idea_id"))
      reject_stale_idea_base!(idea, args["base_version_id"])

      attributes = idea_attributes(args)
      raise ArgumentError, "No idea fields provided" if attributes.empty?

      commit_message = args["commit_message"].presence || "Local agent updated idea"

      Idea.send(:without_history_tracking) do
        idea.transaction do
          idea.update!(attributes)
          idea.create_version(commit_message)
        end
      end

      record_action_event("updated_idea", idea, commit_message, attributes)
      ok(idea: serialize_record(idea.reload))
    end

    def tool_create_note(args)
      idea = user.ideas.find(args.fetch("idea_id"))
      note = idea.notes.create!(
        body: args.fetch("body"),
        parent_note_id: args["parent_note_id"].presence
      )

      record_action_event("created_note", note, "Created note for #{idea.title}", args)
      ok(note: serialize_record(note))
    end

    def tool_create_todo(args)
      idea = user.ideas.find(args.fetch("idea_id"))
      todo = idea.todo_items.create!(title: args.fetch("title"))

      record_action_event("created_todo", todo, "Created todo for #{idea.title}", args)
      ok(todo: serialize_record(todo))
    end

    def tool_update_todo(args)
      todo = user_todo_items.find(args.fetch("todo_id"))
      attributes = args.slice("title")

      if args.key?("completed")
        completed = ActiveModel::Type::Boolean.new.cast(args["completed"]) == true
        completed ? todo.mark_completed! : todo.mark_pending!
      end
      todo.update!(attributes) if attributes.present?

      record_action_event("updated_todo", todo, "Updated todo", args)
      ok(todo: serialize_record(todo.reload))
    end

    def tool_update_build_item(args)
      item = user.build_items.find(args.fetch("build_item_id"))
      attributes = args.slice("title", "description")
      attributes["completed"] = ActiveModel::Type::Boolean.new.cast(args["completed"]) == true if args.key?("completed")
      attributes["completed_at"] = attributes["completed"] ? Time.current : nil if attributes.key?("completed")
      item.update!(attributes) if attributes.present?

      record_action_event("updated_build_item", item, "Updated build item", args)
      ok(build_item: serialize_record(item.reload))
    end

    def tool_approve_submission(args)
      submission = user.submissions.find(args.fetch("submission_id"))
      idea = SubmissionApprover.new(submission).approve!(submission_approval_params(args))

      record_action_event("approved_submission", submission, "Approved submission #{submission.id}", args)
      ok(submission: serialize_record(submission.reload), idea: serialize_record(idea))
    end

    def tool_reject_submission(args)
      submission = user.submissions.find(args.fetch("submission_id"))
      unless destructive_actions_enabled?
        return recommendation_for(
          action: "reject_submission",
          target: submission,
          payload: args,
          reasoning: args["reasoning"].presence || "Rejecting a submission requires review.",
          risk_level: "high"
        )
      end

      submission.reject!(args["review_notes"])
      record_action_event("rejected_submission", submission, "Rejected submission #{submission.id}", args)
      ok(submission: serialize_record(submission.reload))
    end

    def tool_transition_idea(args)
      idea = user.ideas.find(args.fetch("idea_id"))
      state = args.fetch("state").to_s

      if TERMINAL_IDEA_STATES.include?(state) && !destructive_actions_enabled?
        return recommendation_for(
          action: "transition_idea",
          target: idea,
          payload: args,
          reasoning: args["reasoning"].presence || "Terminal idea transitions require review.",
          risk_level: "high"
        )
      end

      transition_idea!(idea, state, args)
      record_action_event("transitioned_idea", idea, "Transitioned idea to #{state.humanize}", args)
      ok(idea: serialize_record(idea.reload))
    end

    def tool_assign_list(args)
      idea = user.ideas.find(args.fetch("idea_id"))
      list = user.lists.find(args.fetch("list_id"))
      idea_list = idea.idea_lists.find_or_create_by!(list: list)

      record_action_event("assigned_list", idea, "Assigned idea to #{list.name}", args)
      ok(idea_list: { id: idea_list.id, idea_id: idea.id, list_id: list.id })
    end

    def tool_assign_topology(args)
      idea = user.ideas.find(args.fetch("idea_id"))
      topology = user.topologies.find(args.fetch("topology_id"))
      idea_topology = idea.idea_topologies.find_or_create_by!(topology: topology)

      record_action_event("assigned_topology", idea, "Assigned idea to #{topology.name}", args)
      ok(idea_topology: { id: idea_topology.id, idea_id: idea.id, topology_id: topology.id })
    end

    def tool_create_fact(args)
      fact = user.facts.create!(body: args.fetch("body"))

      record_action_event("created_fact", fact, "Created fact", args)
      ok(fact: serialize_record(fact))
    end

    def tool_create_maxim(args)
      maxim = user.maxims.create!(body: args.fetch("body"))

      record_action_event("created_maxim", maxim, "Created maxim", args)
      ok(maxim: serialize_record(maxim))
    end

    def tool_run_enrichment(args)
      idea = user.ideas.find(args.fetch("idea_id"))
      job = IdeaEnrichmentJob.perform_later(
        idea.id,
        query: args["query"].presence,
        sources: Array(args["sources"]).presence
      )

      record_action_event("queued_enrichment", idea, "Queued idea enrichment", args)
      ok(job_id: job.job_id, idea: serialize_record(idea))
    end

    def tool_create_recommendation(args)
      target = find_target!(args.fetch("target_type"), args.fetch("target_id"))
      recommendation = create_recommendation!(
        action: args.fetch("action"),
        target: target,
        payload: args["payload"] || {},
        reasoning: args["reasoning"],
        risk_level: args["risk_level"].presence || "medium"
      )

      ok(recommendation_id: recommendation.id, recommendation: serialize_record(recommendation))
    end

    def tool_record_event(args)
      event = record_event!(
        event_type: args.fetch("event_type"),
        target: optional_target(args),
        summary: args["summary"],
        payload: args["payload"] || args.except("event_type", "target_type", "target_id", "summary")
      )

      agent_run&.heartbeat!(args["payload"] || {}) if args["event_type"].to_s == "heartbeat"
      ok(event: serialize_record(event))
    end

    def idea_attributes(args)
      attributes = args.slice(
        "title", "description", "trl", "difficulty", "opportunity", "timing",
        "difficulty_explanation", "opportunity_explanation", "timing_explanation"
      )
      attributes["metadata"] = args["metadata"] if args.key?("metadata")
      attributes
    end

    def reject_stale_idea_base!(idea, base_version_id)
      return if base_version_id.blank?
      return if idea.latest_version&.id.to_s == base_version_id.to_s

      raise ArgumentError, "Base version is stale"
    end

    def submission_approval_params(args)
      args.slice("title", "trl", "difficulty", "opportunity", "timing", "list_id", "topology_ids").symbolize_keys
    end

    def transition_idea!(idea, state, args)
      result = case state
               when "first_try" then idea.transition_to_first_try!
               when "second_try" then idea.transition_to_second_try!
               when "incubating" then idea.fail_attempt!(cool_off_duration(args))
               when "validated" then idea.complete_attempt!
               when "parked" then idea.park!
               when "rejected" then idea.reject!
               when "shipped" then idea.ship!
               when "triage", "idea_new"
                 Idea.send(:without_history_tracking) do
                   idea.transaction do
                     idea.update!(state: state, cool_off_until: nil)
                     idea.create_version("Local agent transitioned to #{state.humanize}")
                   end
                 end
                 true
               else
                 raise ArgumentError, "Unsupported idea state: #{state}"
               end

      raise ArgumentError, "Idea cannot transition to #{state}" unless result
    end

    def user_todo_items
      TodoItem.joins(:idea).where(ideas: { user_id: user.id })
    end

    def cool_off_duration(args)
      days = args["cool_off_days"].presence&.to_i
      days = 7 unless days&.positive?
      days.days
    end

    def optional_target(args)
      return if args["target_type"].blank? || args["target_id"].blank?

      find_target!(args["target_type"], args["target_id"])
    end

    def find_target!(target_type, target_id)
      type = target_type.to_s
      id = target_id.to_s
      raise ArgumentError, "target_type is required" if type.blank?
      raise ArgumentError, "target_id is required" if id.blank?

      case type
      when "User"
        raise ActiveRecord::RecordNotFound, "User not found" unless id == user.id.to_s

        user
      when "Idea"
        user.ideas.find(id)
      when "Submission"
        user.submissions.find(id)
      when "TodoItem"
        user_todo_items.find(id)
      when "Note"
        Note.joins(:idea).where(ideas: { user_id: user.id }).find(id)
      when "BuildItem"
        user.build_items.find(id)
      when "Fact"
        user.facts.find(id)
      when "Maxim"
        user.maxims.find(id)
      when "List"
        user.lists.find(id)
      when "Topology"
        user.topologies.find(id)
      when "AgentRecommendation"
        user.agent_recommendations.find(id)
      when "AgentEvent"
        user.agent_events.find(id)
      else
        raise ArgumentError, "Unsupported target type: #{type}"
      end
    end

    def recommendation_for(action:, target:, payload:, reasoning:, risk_level:)
      recommendation = create_recommendation!(
        action: action,
        target: target,
        payload: payload,
        reasoning: reasoning,
        risk_level: risk_level
      )

      ok(status: "recommended", recommendation_id: recommendation.id, recommendation: serialize_record(recommendation))
    end

    def create_recommendation!(action:, target:, payload:, reasoning:, risk_level:)
      event = record_event!(
        event_type: "recommendation",
        target: target,
        summary: "Recommended #{action}",
        payload: payload.merge("action" => action, "risk_level" => risk_level)
      )

      user.agent_recommendations.create!(
        agent_event: event,
        target: target,
        action: action,
        risk_level: risk_level,
        reasoning: reasoning,
        payload: payload
      )
    end

    def record_action_event(event_type, target, summary, payload)
      record_event!(event_type: event_type, target: target, summary: summary, payload: payload)
    end

    def record_event!(event_type:, target:, summary:, payload:)
      payload ||= {}
      if event_type.to_s == "answer" && target.is_a?(AgentEvent) && target.event_type == "question"
        payload = payload.merge("answer" => summary) if payload["answer"].blank?
      end

      user.agent_events.create!(
        agent_run: agent_run,
        event_type: event_type,
        target: target,
        summary: summary,
        payload: payload
      )
    end

    def serialize_record(record)
      case record
      when User
        serialize_user_context(record)
      when Idea
        serialize_idea(record)
      when Submission
        {
          id: record.id,
          target_type: "Submission",
          title: record.title,
          body: record.body,
          processed_body: record.processed_body.to_plain_text,
          status: record.status,
          priority: record.priority,
          temporary_idea_id: record.temporary_idea_id,
          reviewed_at: record.reviewed_at,
          idea_id: record.idea_id,
          created_at: record.created_at,
          updated_at: record.updated_at
        }
      when TodoItem
        {
          id: record.id,
          target_type: "TodoItem",
          idea_id: record.idea_id,
          title: record.title,
          completed: record.completed?,
          completed_at: record.completed_at,
          position: record.position,
          updated_at: record.updated_at
        }
      when Note
        {
          id: record.id,
          target_type: "Note",
          idea_id: record.idea_id,
          parent_note_id: record.parent_note_id,
          body: record.body,
          depth: record.depth,
          created_at: record.created_at,
          updated_at: record.updated_at
        }
      when BuildItem
        {
          id: record.id,
          target_type: "BuildItem",
          title: record.title,
          description: record.description,
          completed: record.completed?,
          checklist_remaining_count: record.checklist_remaining_count,
          updated_at: record.updated_at
        }
      when Fact, Maxim
        {
          id: record.id,
          target_type: record.class.name,
          body: record.body,
          created_at: record.created_at,
          updated_at: record.updated_at
        }
      when List
        {
          id: record.id,
          target_type: "List",
          name: record.name,
          kind: record.kind,
          idea_count: record.ideas.count,
          updated_at: record.updated_at
        }
      when Topology
        {
          id: record.id,
          target_type: "Topology",
          name: record.name,
          full_path: record.full_path,
          idea_count: record.ideas.count,
          updated_at: record.updated_at
        }
      when AgentRecommendation
        {
          id: record.id,
          target_type: "AgentRecommendation",
          action: record.action,
          risk_level: record.risk_level,
          reasoning: record.reasoning,
          payload: record.payload,
          status: record.status,
          reviewed_at: record.reviewed_at,
          recommendation_target_type: record.target_type,
          recommendation_target_id: record.target_id,
          created_at: record.created_at
        }
      when AgentEvent
        {
          id: record.id,
          target_type: "AgentEvent",
          event_type: record.event_type,
          summary: record.summary,
          payload: record.payload,
          event_target_type: record.target_type,
          event_target_id: record.target_id,
          created_at: record.created_at
        }
      else
        { id: record.id, target_type: record.class.name }
      end
    end

    def serialize_user_context(record)
      {
        id: record.id,
        target_type: "User",
        name: record.name,
        email: record.email,
        counts: {
          ideas: record.ideas.count,
          submissions: record.submissions.count,
          todo_items: TodoItem.joins(:idea).where(ideas: { user_id: record.id }).count,
          build_items: record.build_items.count,
          facts: record.facts.count,
          maxims: record.maxims.count,
          lists: record.lists.count,
          topologies: record.topologies.count
        },
        ideas: record.ideas.non_draft.order(updated_at: :desc).limit(200).map { |idea| serialize_idea(idea) },
        submissions: record.submissions.recent.limit(100).map { |submission| serialize_record(submission) },
        build_items: record.build_items.order(updated_at: :desc).limit(100).map { |item| serialize_record(item) },
        facts: record.facts.recent.limit(100).map { |fact| serialize_record(fact) },
        maxims: record.maxims.recent.limit(100).map { |maxim| serialize_record(maxim) },
        lists: record.lists.ordered.limit(100).map { |list| serialize_record(list) },
        topologies: record.topologies.ordered.limit(100).map { |topology| serialize_record(topology) },
        pending_recommendations: record.agent_recommendations.pending.recent.limit(50).map { |recommendation| serialize_record(recommendation) },
        recent_agent_events: record.agent_events.where.not(event_type: "heartbeat").recent.limit(50).map { |event| serialize_record(event) }
      }
    end

    def serialize_idea(idea)
      {
        id: idea.id,
        target_type: "Idea",
        title: idea.title,
        description: idea.description.to_plain_text,
        state: idea.state,
        trl: idea.trl,
        difficulty: idea.difficulty,
        opportunity: idea.opportunity,
        timing: idea.timing,
        computed_score: idea.computed_score,
        metadata: idea.metadata,
        latest_version_id: idea.latest_version&.id,
        todo_items: idea.todo_items.order(:position).map { |todo| serialize_record(todo) },
        notes: idea.notes.recent_first.limit(10).map { |note| serialize_record(note) },
        lists: idea.lists.ordered.map { |list| { id: list.id, name: list.name, kind: list.kind } },
        topologies: idea.topologies.ordered.map { |topology| { id: topology.id, name: topology.name, full_path: topology.full_path } },
        ocr_attachments: idea.ocr_attachment_parts.map do |part|
          {
            attachment_id: part[:attachment].id,
            filename: part[:attachment].filename.to_s,
            text: part[:text]
          }
        end,
        created_at: idea.created_at,
        updated_at: idea.updated_at
      }
    end
  end
end
