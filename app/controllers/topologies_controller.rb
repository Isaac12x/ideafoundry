class TopologiesController < ApplicationController
  before_action :set_user
  before_action :set_topology, only: [:show, :edit, :update, :destroy, :reorder, :neighborhood]

  def index
    @topologies = @user.topologies.roots.ordered.includes(children: { children: { children: :children } })
    @default_view = @user.topology_settings['default_view'] || 'tree'
  end

  def show
    @children = @topology.children.ordered
    @ideas = @topology.ideas
  end

  def new
    @topology = @user.topologies.build
    @parent_options = @user.topologies.ordered
  end

  def create
    @topology = @user.topologies.build(topology_params)

    if @topology.save
      respond_to do |format|
        format.html { redirect_to topologies_path, notice: 'Topology created.' }
        format.json { render json: @topology, status: :created }
      end
    else
      @parent_options = @user.topologies.ordered
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @topology.errors }, status: :unprocessable_entity }
      end
    end
  end

  def edit
    @parent_options = @user.topologies.where.not(id: [@topology.id] + @topology.descendants.map(&:id)).ordered
  end

  def update
    if @topology.update(topology_params)
      if params[:topology_overrides].present?
        overrides = params[:topology_overrides].permit(*User::ALLOWED_TOPOLOGY_OVERRIDE_KEYS).to_h
        overrides.reject! { |_, v| v.blank? }
        overrides.transform_values! do |v|
          case v
          when 'true' then true
          when 'false' then false
          else v.match?(/\A-?\d+\.?\d*\z/) ? v.to_f : v
          end
        end
        @user.update_topology_overrides(@topology.id, overrides)
      end

      respond_to do |format|
        format.html { redirect_to topologies_path, notice: 'Topology updated.' }
        format.json { render json: @topology }
      end
    else
      @parent_options = @user.topologies.where.not(id: [@topology.id] + @topology.descendants.map(&:id)).ordered
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @topology.errors }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @topology.destroy
    respond_to do |format|
      format.html { redirect_to topologies_path, notice: 'Topology deleted.' }
      format.json { head :no_content }
    end
  end

  def graph_data
    topologies = @user.topologies.includes(:ideas, :parent)
    root_cache = {}
    nodes = []
    links = []

    topologies.each do |t|
      root = root_cache[t.id] ||= t.find_root
      root_color = root.color.presence || '#d4953a'

      nodes << {
        id: "t_#{t.id}",
        name: t.name,
        color: t.color.presence || '#d4953a',
        type: 'topology',
        url: topology_path(t),
        val: 3 + t.ideas.size,
        root_id: "t_#{root.id}",
        root_color: root_color
      }

      if t.parent_id.present?
        links << { source: "t_#{t.parent_id}", target: "t_#{t.id}", type: 'parent' }
      end

      t.ideas.each do |idea|
        unless nodes.any? { |n| n[:id] == "i_#{idea.id}" }
          nodes << {
            id: "i_#{idea.id}",
            name: idea.title,
            color: root_color,
            type: 'idea',
            url: idea_path(idea),
            val: 2,
            root_id: "t_#{root.id}",
            root_color: root_color
          }
        end
        links << { source: "t_#{t.id}", target: "i_#{idea.id}", type: 'idea' }
      end
    end

    render json: { nodes: nodes, links: links, settings: graph_settings_for_response }
  end

  def neighborhood
    scope = [@topology] + @topology.ancestors + @topology.children.to_a
    siblings = @topology.parent ? @topology.parent.children.where.not(id: @topology.id).to_a : []
    scope += siblings

    # Eager load ideas for all scoped topologies
    scope_ids_list = scope.uniq.map(&:id)
    preloaded = @user.topologies.where(id: scope_ids_list).includes(:ideas).index_by(&:id)

    nodes = []
    links = []

    scope_ids = scope_ids_list.to_set

    root_cache = {}

    scope.uniq.each do |t|
      t = preloaded[t.id] || t
      root = root_cache[t.id] ||= t.find_root
      root_color = root.color.presence || '#d4953a'

      nodes << {
        id: "t_#{t.id}",
        name: t.name,
        color: t.color.presence || '#d4953a',
        type: 'topology',
        url: topology_path(t),
        val: t.id == @topology.id ? 8 : 3 + t.ideas.size,
        root_id: "t_#{root.id}",
        root_color: root_color
      }

      if t.parent_id.present? && scope_ids.include?(t.parent_id)
        links << { source: "t_#{t.parent_id}", target: "t_#{t.id}", type: 'parent' }
      end

      t.ideas.each do |idea|
        unless nodes.any? { |n| n[:id] == "i_#{idea.id}" }
          nodes << {
            id: "i_#{idea.id}",
            name: idea.title,
            color: root_color,
            type: 'idea',
            url: idea_path(idea),
            val: 2,
            root_id: "t_#{root.id}",
            root_color: root_color
          }
        end
        links << { source: "t_#{t.id}", target: "i_#{idea.id}", type: 'idea' }
      end
    end

    render json: { nodes: nodes, links: links, settings: graph_settings_for_response(@topology.id) }
  end

  def reorder
    params[:topology_ids].each_with_index do |id, index|
      @user.topologies.find(id).update(position: index + 1)
    end

    respond_to do |format|
      format.json { render json: { status: 'success' } }
      format.html { redirect_to topologies_path }
    end
  end

  private

  def set_topology
    @topology = @user.topologies.find(params[:id])
  end

  def topology_params
    params.require(:topology).permit(:name, :parent_id, :color, :topology_type, :position)
  end

  def graph_settings_for_response(topology_id = nil)
    if topology_id
      @user.topology_overrides_for(topology_id)
    else
      @user.topology_settings
    end
  end
end
