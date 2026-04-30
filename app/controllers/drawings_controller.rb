class DrawingsController < ApplicationController
  before_action :set_user
  before_action :set_idea
  before_action :set_drawing, only: [:show, :update, :destroy]

  # JSON / multipart saves come from the React app via fetch(); skip CSRF for those.
  skip_before_action :verify_authenticity_token, only: [:create, :update]

  def new
    @drawing = @idea.drawings.build(role: parse_role(params[:role]) || :general)
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: drawing_json(@drawing) }
    end
  end

  def create
    @drawing = @idea.drawings.build(drawing_params)
    attach_png_from_data_url

    if @drawing.save
      render json: drawing_json(@drawing), status: :created
    else
      render json: { errors: @drawing.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    @drawing.assign_attributes(drawing_params)
    attach_png_from_data_url

    if @drawing.save
      render json: drawing_json(@drawing), status: :ok
    else
      render json: { errors: @drawing.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    @drawing.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "drawings_tab_#{@idea.id}",
          partial: "drawings/tab",
          locals: { idea: @idea }
        )
      end
      format.json { head :no_content }
      format.html { redirect_to idea_path(@idea, anchor: "drawing"), notice: "Drawing deleted." }
    end
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end

  def set_drawing
    @drawing = @idea.drawings.find(params[:id])
  end

  def drawing_params
    raw = params.require(:drawing)
    permitted = raw.permit(:title, :role, :position)

    if raw.key?(:content)
      content = raw[:content]
      permitted[:content] = case content
                            when String then JSON.parse(content)
                            when ActionController::Parameters then content.permit!.to_h
                            else content
                            end
    end

    permitted[:role] = parse_role(permitted[:role]) if permitted[:role].present?
    permitted
  end

  def parse_role(value)
    return nil if value.blank?
    Drawing.roles.key?(value.to_s) ? value.to_s : nil
  end

  def attach_png_from_data_url
    raw = params.dig(:drawing, :png_data_url)
    return if raw.blank?

    match = raw.match(/\Adata:(image\/[\w+.-]+);base64,(.+)\z/m)
    return unless match

    content_type = match[1]
    decoded = Base64.decode64(match[2])
    @drawing.rendered_png.attach(
      io: StringIO.new(decoded),
      filename: "drawing-#{Time.now.to_i}.png",
      content_type: content_type
    )
  end

  def drawing_json(drawing)
    {
      id: drawing.id,
      title: drawing.title,
      role: drawing.role,
      position: drawing.position,
      png_url: drawing.png_url,
      content: drawing.content
    }
  end
end
