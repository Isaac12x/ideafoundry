# Built-in patent Reference (Patent Notes). Static, shipped content: no per-user data.
class ReferenceController < ApplicationController
  def index
    @q = params[:q].to_s.strip
    @results = PatentReference.search(@q, limit: 20) if @q.present?
    @clusters = PatentReference.by_cluster
  end

  def show
    @note = PatentReference.find(params[:slug]) or raise ActionController::RoutingError, "Patent Note not found"
    @related = @note.related.filter_map { |s| PatentReference.find(s) }
  end
end
