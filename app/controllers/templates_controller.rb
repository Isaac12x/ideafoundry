class TemplatesController < ApplicationController
  before_action :set_user
  before_action :set_template, only: [:show, :edit, :update, :destroy, :apply]

  def index
    @templates = @user.templates.order(:name)
    @default_template = @templates.find_by(is_default: true)
  end

  def show
    respond_to do |format|
      format.html
      format.json do
        render json: {
          id: @template.id,
          name: @template.name,
          is_default: @template.is_default?,
          field_definitions: @template.field_definitions,
          section_order: @template.section_order,
          tab_definitions: @template.effective_tab_definitions
        }
      end
    end
  end

  def new
    @template = @user.templates.build
    # Set default field definitions and section order
    @template.field_definitions = []
    @template.section_order = []
    @template.tab_definitions = default_tab_definitions
  end

  def create
    @template = @user.templates.build(template_params)
    
    if @template.save
      redirect_to settings_templates_path, notice: 'Template was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      redirect_to @template, notice: 'Template was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @template.is_default?
      redirect_to templates_path, alert: 'Cannot delete the default template.'
      return
    end
    
    @template.destroy
    redirect_to templates_path, notice: 'Template was successfully deleted.'
  end

  def apply
    @idea = @user.ideas.find(params[:idea_id])
    
    if @idea.apply_template(@template)
      @idea.save!
      redirect_to @idea, notice: 'Template applied successfully.'
    else
      redirect_to @idea, alert: 'Failed to apply template.'
    end
  end

  private

  def set_template
    @template = @user.templates.find(params[:id])
  end

  def template_params
    permitted = params.require(:template).permit(:name, :is_default)

    # section_order comes as indexed hash keys — convert to array
    if params[:template][:section_order].present?
      raw = params[:template][:section_order]
      permitted[:section_order] = raw.is_a?(Array) ? raw : raw.to_unsafe_h.sort_by { |k, _| k.to_i }.map(&:last)
    end

    # field_definitions come as nested hashes (e.g. field_definitions[0][name])
    if params[:template][:field_definitions].present?
      raw = params[:template][:field_definitions]
      permitted[:field_definitions] = raw.to_unsafe_h.sort_by { |k, _| k.to_i }.map do |_, fd|
        fd = fd.slice('name', 'label', 'type', 'default_value', 'placeholder', 'required', 'options', 'tab', 'position', 'instance_id')
        fd['required'] = fd['required'] == 'true'
        fd['options'] = fd['options'].split(',').map(&:strip) if fd['options'].present?
        fd['position'] = fd['position'].to_i if fd['position'].present?
        fd['instance_id'] ||= "#{fd['name']}_#{SecureRandom.hex(4)}" if fd['name'].present?
        fd
      end
    end

    # tab_definitions come as nested hashes
    if params[:template][:tab_definitions].present?
      raw = params[:template][:tab_definitions]
      permitted[:tab_definitions] = raw.to_unsafe_h.sort_by { |k, _| k.to_i }.map do |_, td|
        td = td.slice('name', 'label', 'position')
        td['position'] = td['position'].to_i if td['position'].present?
        td
      end
    end

    permitted
  end

  def default_field_definitions
    [
      {
        'name' => 'priority',
        'label' => 'Priority',
        'type' => 'select',
        'options' => ['Low', 'Medium', 'High', 'Critical'],
        'required' => false,
        'default_value' => 'Medium',
        'tab' => 'general',
        'position' => 0
      },
      {
        'name' => 'target_market',
        'label' => 'Target Market',
        'type' => 'textarea',
        'required' => false,
        'placeholder' => 'Describe your target market...',
        'tab' => 'general',
        'position' => 1
      }
    ]
  end

  def default_tab_definitions
    [{ 'name' => 'general', 'label' => 'General', 'position' => 0 }]
  end

  def default_section_order
    %w[header stats description media metadata timeline]
  end
end
