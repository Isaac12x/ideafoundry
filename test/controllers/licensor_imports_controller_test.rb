require "test_helper"

class LicensorImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "li-test@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Licensable Idea", for_licensing: true)
  end

  # Header wording in the fixture is deliberately loose ("Company Name",
  # "Contact") so the auto-mapping is exercised alongside the flow.
  def upload_fixture(name = "licensors.csv", type = "text/csv")
    post idea_licensor_imports_path(@idea),
         params: { file: fixture_file_upload(name, type) }
    LicensorImport.order(:id).last
  end

  def mapping_for(import)
    { "0" => "company", "1" => "contact_name", "2" => "contact_email", "3" => "stage", "4" => "notes" }
  end

  test "new renders the upload screen" do
    get new_idea_licensor_import_path(@idea)
    assert_response :success
    assert_match "Drop a CSV or Excel file", response.body
  end

  test "upload stores the file and lands on the mapping screen" do
    assert_difference("LicensorImport.count", 1) do
      upload_fixture
    end
    import = LicensorImport.order(:id).last
    assert import.file.attached?
    assert_equal "licensors.csv", import.filename
    assert_redirected_to licensor_import_path(import)
  end

  test "mapping screen previews the sheet and pre-selects guessed fields" do
    import = upload_fixture
    get licensor_import_path(import)

    assert_response :success
    assert_match "Acme Publishing", response.body
    assert_match "mapping[0]", response.body
    # "Company Name" -> company, "Email" -> contact_email, both auto-guessed.
    assert_match(/name="mapping\[0\]".*?<option selected="selected" value="company"/m, response.body)
    assert_match(/name="mapping\[2\]".*?<option selected="selected" value="contact_email"/m, response.body)
  end

  test "unsupported file types are rejected before anything is stored" do
    assert_no_difference("LicensorImport.count") do
      post idea_licensor_imports_path(@idea),
           params: { file: fixture_file_upload("welcome.eml", "message/rfc822") }
    end
    assert_response :unprocessable_content
  end

  test "importing creates licensors, skips blank and duplicate rows" do
    import = upload_fixture

    # 5 data rows: 3 importable, 1 with no company, 1 duplicate of the first.
    assert_difference("Licensor.count", 3) do
      patch licensor_import_path(import), params: { headers_in_first_row: "1", mapping: mapping_for(import) }
    end
    assert_redirected_to licensing_crm_path

    companies = @idea.licensors.pluck(:company)
    assert_equal [ "Acme Publishing", "Borealis Media", "Cobalt Games" ], companies.sort
    assert_equal "contacted", @idea.licensors.find_by(company: "Acme Publishing").stage
    assert_equal "negotiating", @idea.licensors.find_by(company: "Borealis Media").stage
  end

  test "an unreadable email is parked in notes instead of failing the row" do
    import = upload_fixture
    patch licensor_import_path(import), params: { headers_in_first_row: "1", mapping: mapping_for(import) }

    cobalt = @idea.licensors.find_by(company: "Cobalt Games")
    assert_equal "", cobalt.contact_email
    assert_match "Imported email: not-an-email", cobalt.notes
    assert_equal "identified", cobalt.stage, "a blank stage cell starts at the top of the funnel"
  end

  test "the mapping and file are kept so the import can be reopened" do
    import = upload_fixture
    patch licensor_import_path(import), params: { headers_in_first_row: "1", mapping: mapping_for(import) }

    import.reload
    assert_equal "imported", import.status
    assert_equal 3, import.imported_count
    assert_equal 5, import.row_count
    assert_equal "company", import.mapping["0"]
    assert import.file.attached?
  end

  test "re-running an import does not duplicate what it already created" do
    import = upload_fixture
    patch licensor_import_path(import), params: { headers_in_first_row: "1", mapping: mapping_for(import) }

    assert_no_difference("Licensor.count") do
      patch licensor_import_path(import), params: { headers_in_first_row: "1", mapping: mapping_for(import) }
    end
  end

  test "treating row one as data imports the header row too" do
    import = upload_fixture
    patch licensor_import_path(import), params: { headers_in_first_row: "0", mapping: mapping_for(import) }

    assert @idea.licensors.exists?(company: "Company Name")
    assert_equal 4, import.reload.imported_count
  end

  test "company must be mapped" do
    import = upload_fixture
    assert_no_difference("Licensor.count") do
      patch licensor_import_path(import), params: { headers_in_first_row: "1", mapping: { "2" => "contact_email" } }
    end
    assert_response :unprocessable_content
    assert_match "Map one column to Company", response.body
  end

  test "one field cannot claim two columns" do
    import = upload_fixture
    patch licensor_import_path(import),
          params: { headers_in_first_row: "1", mapping: { "0" => "company", "1" => "company" } }

    assert_response :unprocessable_content
    assert_match "mapped to more than one column", response.body
  end

  test "importing flags the idea for licensing so the rows show in the CRM" do
    @idea.update!(for_licensing: false)
    import = upload_fixture
    patch licensor_import_path(import), params: { headers_in_first_row: "1", mapping: mapping_for(import) }

    assert @idea.reload.for_licensing?
  end

  test "destroy discards the import but leaves created licensors alone" do
    import = upload_fixture
    patch licensor_import_path(import), params: { headers_in_first_row: "1", mapping: mapping_for(import) }

    assert_no_difference("Licensor.count") do
      assert_difference("LicensorImport.count", -1) do
        delete licensor_import_path(import)
      end
    end
    assert_redirected_to new_idea_licensor_import_path(@idea)
  end

  test "an Excel upload is read the same way as a CSV" do
    path = Rails.root.join("tmp", "licensors-#{SecureRandom.hex(6)}.xlsx").to_s
    pkg = Axlsx::Package.new
    pkg.workbook.add_worksheet(name: "Prospects") do |sheet|
      sheet.add_row [ "Company", "Email", "Deal stage" ]
      sheet.add_row [ "Delta Interactive", "hi@delta.test", "Meeting" ]
      # A numeric cell: Roo hands back a Float, which must not render as "12.0".
      sheet.add_row [ "Echo Ltd", "hi@echo.test", 12 ]
    end
    pkg.serialize(path)

    post idea_licensor_imports_path(@idea),
         params: { file: Rack::Test::UploadedFile.new(path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") }
    import = LicensorImport.order(:id).last

    get licensor_import_path(import)
    assert_response :success
    assert_match "Delta Interactive", response.body
    assert_match ">12<", response.body

    assert_difference("Licensor.count", 2) do
      patch licensor_import_path(import),
            params: { headers_in_first_row: "1", mapping: { "0" => "company", "1" => "contact_email", "2" => "stage" } }
    end
    assert_equal "meeting", @idea.licensors.find_by(company: "Delta Interactive").stage
    assert_equal "identified", @idea.licensors.find_by(company: "Echo Ltd").stage
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "a sheet with no rows sends the user back to the upload screen" do
    empty = Rails.root.join("tmp", "empty-#{SecureRandom.hex(6)}.csv").to_s
    File.write(empty, "")
    post idea_licensor_imports_path(@idea), params: { file: Rack::Test::UploadedFile.new(empty, "text/csv") }
    import = LicensorImport.order(:id).last

    get licensor_import_path(import)
    assert_redirected_to new_idea_licensor_import_path(@idea)
    assert_match(/no rows/i, flash[:alert])
  ensure
    File.delete(empty) if empty && File.exist?(empty)
  end

  test "another user's import is not reachable" do
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", name: "Other")
    other_idea = other.ideas.create!(title: "Theirs", for_licensing: true)
    other_import = other_idea.licensor_imports.new(filename: "x.csv")
    other_import.file.attach(io: StringIO.new("Company\nSecret Co\n"), filename: "x.csv", content_type: "text/csv")
    other_import.save!

    skip "single-user app: User.first is the other user" if User.first == other

    get licensor_import_path(other_import)
    assert_response :not_found
  end
end
