# Looks a Problem up on Wikipedia + Grokipedia and imports the matches next to problem.md.
class ProblemLookupJob < ApplicationJob
  queue_as :default

  def perform(id)
    problem = Problem.find_by(id: id) or return
    problem.update!(status: "running")
    broadcast(problem)
    found = Kb::ProblemResearch.run!(problem)
    problem.update!(status: "done", result: found.empty? ? "Nothing found" : found.map { |f| "#{f[:site]}: #{f[:title]}" }.join(" · "))
  rescue StandardError => e
    Rails.logger.warn("ProblemLookupJob #{id}: #{e.class}: #{e.message}")
    problem&.update(status: "failed", result: e.message.truncate(200))
  ensure
    if problem
      broadcast(problem)
      Kb::TreeBroadcaster.call(problem.user)
    end
  end

  private

  def broadcast(problem)
    Turbo::StreamsChannel.broadcast_replace_to([ problem.user, "kb_tree" ], target: ActionView::RecordIdentifier.dom_id(problem),
                                               partial: "problems/problem", locals: { problem: problem })
  end
end
