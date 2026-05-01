require "test_helper"

class NapkinHelperTest < ActionView::TestCase
  include NapkinHelper

  def data(cells, rows: 10, cols: 5)
    { "rows" => rows, "cols" => cols, "cells" => cells }
  end

  test "evaluate plain numbers and text" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "Users", "fmt" => nil },
      "B1" => { "raw" => "1000",  "fmt" => nil }
    }))
    assert_equal "Users", result["A1"][:display]
    assert_equal "1000",  result["B1"][:display]
    assert_nil result["A1"][:error]
  end

  test "evaluate basic arithmetic formula" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "10",     "fmt" => nil },
      "B1" => { "raw" => "20",     "fmt" => nil },
      "C1" => { "raw" => "=A1+B1", "fmt" => nil }
    }))
    assert_equal "30", result["C1"][:display]
  end

  test "evaluate SUM range" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "1",      "fmt" => nil },
      "A2" => { "raw" => "2",      "fmt" => nil },
      "A3" => { "raw" => "3",      "fmt" => nil },
      "B1" => { "raw" => "=SUM(A1:A3)", "fmt" => nil }
    }))
    assert_equal "6", result["B1"][:display]
  end

  test "evaluate IF and ROUND" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "5", "fmt" => nil },
      "B1" => { "raw" => "=IF(A1>3, ROUND(A1*1.111, 2), 0)", "fmt" => nil }
    }))
    assert_equal "5.56", result["B1"][:display]
  end

  test "format_napkin_cell — currency" do
    assert_equal "$1,500.00", format_napkin_cell("1500", "currency:USD:2", 1500.0)
  end

  test "format_napkin_cell — percent" do
    assert_equal "75.0%", format_napkin_cell("0.75", "percent:1", 0.75)
  end

  test "format_napkin_cell — number with decimals" do
    assert_equal "3.14", format_napkin_cell("3.14159", "number:2", 3.14159)
  end

  test "format_napkin_cell — bold-only fmt preserves number formatting" do
    assert_equal "1000", format_napkin_cell("1000", "bold", 1000)
  end

  test "format_napkin_cell — bold|currency stacks" do
    out = format_napkin_cell("100", "bold|currency:USD:0", 100)
    assert_equal "$100", out
  end

  test "evaluate handles bad formula with error" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "=NOTAFUNCTION()", "fmt" => nil }
    }))
    assert_equal "#ERR", result["A1"][:display]
    assert_not_nil result["A1"][:error]
  end

  test "evaluate handles cycle" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "=B1", "fmt" => nil },
      "B1" => { "raw" => "=A1", "fmt" => nil }
    }))
    assert_equal "#CYCLE", result["A1"][:display]
  end
end
