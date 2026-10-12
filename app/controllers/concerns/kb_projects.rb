# Project pages for the KB: project -> tests -> runs. Every path is resolved
# through Kb::YamlNode.safe_abs (via the Kb::* models) inside a writable source.
module KbProjects
  extend ActiveSupport::Concern

  UNNAMED_PROJECT = "Untitled project".freeze
  UNNAMED_TEST = "Untitled test".freeze

  included do
    helper_method :render_markdown, :measurement_table, :project_image?
  end

  def project_show
    project_action(exact: true) { |base, project| render_project_page(base, project) }
  end

  def project_update
    project_action(exact: true) do |_base, project|
      project.update!(params.permit(:goal, :status, :private, :conclusion).to_h)
      redirect_to kb_project_path(src: params[:src], path: project.rel)
    end
  end

  def project_convert
    base = writable_base(params[:src].to_i)
    return fs_error("Folder is not available.") if base.nil?

    Kb::Project.convert!(base: base, rel: params[:path].to_s)
    respond_fs
  rescue ArgumentError => error
    fs_error(error.message)
  end

  # dir is the project folder or its Tests folder. No name = placeholder test
  # that drops into inline naming in the tree.
  def project_test_create
    project_action(rel_param: :dir) do |base, project|
      dir = params[:dir].to_s.sub(%r{/+\z}, "")
      unless [project.rel, File.join(project.rel, Kb::Project::TESTS_DIR)].include?(dir)
        raise ArgumentError, "Tests live inside a project."
      end

      name = params[:name].to_s.strip
      attrs = params.permit(:objective, :protocol).to_h.symbolize_keys
      if name.blank?
        test = project.create_test!(name: unique_test_name(project), **attrs)
        next respond_fs(editing: test.rel)
      end
      project.create_test!(name: name, **attrs)
      respond_project(base, project)
    end
  end

  def project_test_update
    project_action do |base, project|
      test = project_test(base, project, params[:path].to_s) or next head(:not_found)
      test.update!(params.permit(:objective, :protocol).to_h)
      redirect_to kb_project_path(src: params[:src], path: project.rel)
    end
  end

  # Any folder directly under Tests/ counts, including hand-made ones without metadata.
  def project_test_destroy
    project_action do |base, project|
      rel = params[:path].to_s.sub(%r{/+\z}, "")
      prefix = File.join(project.rel, Kb::Project::TESTS_DIR) + "/"
      name = rel.delete_prefix(prefix)
      abs = Kb::YamlNode.safe_abs(base, rel)
      raise ArgumentError, "Test not found." unless rel.start_with?(prefix) && !name.include?("/") && abs && File.directory?(abs)

      FileUtils.rm_r(abs)
      KbEntryPreference.delete_subtree!(user: @user, source_path: base, relative_path: rel)
      IdeaKbLink.delete_subtree!(user: @user, source_path: base, relative_path: rel)
      respond_project(base, project)
    end
  end

  def project_run_create
    project_action do |base, project|
      test = project_test(base, project, params[:path].to_s) or next head(:not_found)
      run = test.create_run!(**run_attrs)
      store_run_files(run)
      respond_project(base, project)
    end
  end

  def project_run_update
    project_action do |base, project|
      run = project_run(base, project, params[:path].to_s) or next head(:not_found)
      run.update!(run_attrs)
      store_run_files(run)
      respond_project(base, project)
    end
  end

  # Rows = measurement names present in >= 2 runs; cells line up with the runs
  # that logged any measurement. delta = change vs the previous numeric value.
  def measurement_table(runs)
    logged = runs.select { |run| run.measurements.any? }
    names = logged.flat_map { |run| run.measurements.map { |m| m["name"] }.uniq }.tally.select { |_, n| n >= 2 }.keys
    return nil if names.empty?

    rows = names.map do |name|
      previous = nil
      cells = logged.map do |run|
        m = run.measurements.find { |item| item["name"] == name }
        next nil unless m

        number = Float(m["value"], exception: false)
        delta = number && previous ? (number - previous).round(6) : nil
        previous = number if number
        { value: m["value"], unit: m["unit"], delta: delta }
      end
      { name: name, cells: cells }
    end
    { runs: logged, rows: rows }
  end

  def project_image?(name)
    Kb::MediaTypes::IMAGE_EXTENSIONS.include?(File.extname(name).downcase)
  end

  private

  # Resolves the project for params[rel_param]; exact => that folder must be the project.
  def project_action(rel_param: :path, exact: false)
    base = writable_base(params[:src].to_i)
    rel = params[rel_param].to_s.sub(%r{/+\z}, "")
    project = base && Kb::Project.containing(base, rel)
    return head(:not_found) if project.nil? || (exact && project.rel != rel)

    yield base, project
  rescue ArgumentError => error
    flash[:alert] = error.message
    redirect_to(project ? kb_project_path(src: params[:src], path: project.rel) : kb_path)
  end

  def render_project_page(base, project)
    @project = project
    @src = params[:src].to_i
    @entries = project_entries(project)
    @backlinks = IdeaKbLink.for_path(user: @user, source_path: base, relative_path: project.rel).includes(:idea).order(:id)
    render "kb/project_show"
  end

  # Tests/Run folders change the tree, so those answers refresh it too.
  def respond_project(base, project)
    return redirect_to(kb_project_path(src: params[:src], path: project.rel)) unless request.format.turbo_stream?

    @folders = build_folder_tree
    @project = project
    @src = params[:src].to_i
    @entries = project_entries(project)
    @backlinks = IdeaKbLink.for_path(user: @user, source_path: base, relative_path: project.rel).includes(:idea).order(:id)
    render "kb/project_stream"
  end

  # Non-Tests, non-dot children of the project folder.
  def project_entries(project)
    Dir.children(project.abs).reject { |c| c.start_with?(".") || c == Kb::Project::TESTS_DIR || File.symlink?(File.join(project.abs, c)) }
       .sort.map { |c| { name: c, rel: File.join(project.rel, c), dir: File.directory?(File.join(project.abs, c)) } }
  end

  def project_test(base, project, rel)
    prefix = File.join(project.rel, Kb::Project::TESTS_DIR) + "/"
    return nil unless rel.start_with?(prefix) && !rel.delete_prefix(prefix).include?("/")

    test = Kb::ProjectTest.new(base, rel, project)
    test.abs && File.file?(File.join(test.abs, Kb::ProjectTest::META_FILE)) ? test : nil
  end

  def project_run(base, project, rel)
    test = project_test(base, project, File.dirname(rel))
    return nil unless test

    run = Kb::TestRun.new(base, rel, test)
    run.abs && File.file?(File.join(run.abs, Kb::TestRun::META_FILE)) ? run : nil
  end

  def run_attrs
    permitted = params.permit(:date, :conditions, :result, measurements: [:name, :value, :unit]).to_h
    attrs = { date: permitted[:date].presence || Date.current.iso8601,
              conditions: permitted[:conditions].to_s, result: permitted[:result].to_s,
              measurements: permitted[:measurements] || [] }
    attrs
  end

  # Same safety as fs_upload: basename only, never overwrite.
  def store_run_files(run)
    Array(params[:files]).select { |upload| upload.respond_to?(:tempfile) }.each do |upload|
      name = sanitized_upload_name(upload.original_filename)
      next if name.blank?

      upload.tempfile.rewind
      File.open(unique_fs_path(File.join(run.abs, name)), "wb") { |file| IO.copy_stream(upload.tempfile, file) }
    end
  end

  def unique_test_name(project)
    dir = File.join(project.abs, Kb::Project::TESTS_DIR)
    File.basename(unique_fs_path(File.join(dir, UNNAMED_TEST)))
  end

  def project_create(parent, name)
    base = writable_base(params[:src].to_i)
    name = File.basename(unique_fs_path(File.join(parent, UNNAMED_PROJECT))) if name.blank?
    project = Kb::Project.create!(base: base, parent_rel: params[:dir].to_s, name: name, goal: params[:goal].to_s)
    respond_fs(editing: project.rel)
  rescue ArgumentError => error
    fs_error(error.message)
  end
end
