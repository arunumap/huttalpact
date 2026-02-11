require "test_helper"

class KeyClauseTest < ActiveSupport::TestCase
  setup do
    @clause = key_clauses(:termination_clause)
  end

  test "valid key clause" do
    assert @clause.valid?
  end

  test "requires clause_type" do
    @clause.clause_type = nil
    assert_not @clause.valid?
    assert_includes @clause.errors[:clause_type], "can't be blank"
  end

  test "validates clause_type inclusion" do
    @clause.clause_type = "unknown_type"
    assert_not @clause.valid?
    assert_includes @clause.errors[:clause_type], "is not included in the list"
  end

  test "requires content" do
    @clause.content = nil
    assert_not @clause.valid?
    assert_includes @clause.errors[:content], "can't be blank"
  end

  test "validates confidence_score range" do
    @clause.confidence_score = -1
    assert_not @clause.valid?

    @clause.confidence_score = 101
    assert_not @clause.valid?

    @clause.confidence_score = 50
    assert @clause.valid?
  end

  test "allows nil confidence_score" do
    @clause.confidence_score = nil
    assert @clause.valid?
  end

  test "belongs to contract" do
    assert_equal contracts(:hvac_maintenance), @clause.contract
  end

  test "clause_type_label returns formatted type" do
    assert_equal "Termination", @clause.clause_type_label
    assert_equal "Penalty", key_clauses(:penalty_clause).clause_type_label
  end

  test "confidence_level returns high for >= 80" do
    @clause.confidence_score = 92
    assert_equal :high, @clause.confidence_level
  end

  test "confidence_level returns medium for 50-79" do
    @clause.confidence_score = 75
    assert_equal :medium, @clause.confidence_level
  end

  test "confidence_level returns low for < 50" do
    @clause.confidence_score = 30
    assert_equal :low, @clause.confidence_level
  end

  test "confidence_level returns nil when no score" do
    @clause.confidence_score = nil
    assert_nil @clause.confidence_level
  end

  test "high_confidence scope" do
    high = KeyClause.high_confidence
    assert_includes high, key_clauses(:termination_clause)
    assert_includes high, key_clauses(:renewal_clause)
    assert_not_includes high, key_clauses(:penalty_clause)
  end

  test "by_type scope" do
    termination = KeyClause.by_type("termination")
    assert_includes termination, key_clauses(:termination_clause)
    assert_not_includes termination, key_clauses(:renewal_clause)
  end

  test "CLAUSE_TYPES constant" do
    expected = %w[termination renewal penalty sla price_escalation liability insurance_requirement]
    assert_equal expected, KeyClause::CLAUSE_TYPES
  end
end
