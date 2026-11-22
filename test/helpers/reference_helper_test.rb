require "test_helper"

class ReferenceHelperTest < ActionView::TestCase
  test "labels official sources by citation" do
    {
      "https://www.uspto.gov/web/offices/pac/mpep/s2106.html#x" => "MPEP § 2106",
      "https://www.uspto.gov/web/offices/pac/mpep/mpep-2100.html" => "MPEP ch. 2100",
      "https://www.ecfr.gov/current/title-37/chapter-I/subchapter-A/part-1/subpart-B/section-1.84" => "37 CFR § 1.84",
      "https://www.law.cornell.edu/uscode/text/35/101" => "35 U.S.C. § 101",
      "https://www.epo.org/en/legal/guidelines-epc/2024/g_ii_3_6.html" => "EPO Guidelines G-II, 3.6",
      "https://patentcenter.uspto.gov/" => "Patent Center"
    }.each { |url, label| assert_equal label, reference_source_label(url).first, url }
  end

  test "every shipped link gets a non-empty label" do
    PatentReference.all.flat_map(&:links).each { |u| assert reference_source_label(u).first.present?, u }
  end
end
