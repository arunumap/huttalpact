require "test_helper"

class ReviewMilestoneArrayEditorTest < ActiveSupport::TestCase
  test "update mutates a milestone by index" do
    editor = ReviewMilestoneArrayEditor.new(
      [
        { milestone_type: "custom", due_date: "2025-05-01", description: "Original", recurring: false }
      ].to_json
    )

    updated = editor.update(
      index: 0,
      attrs: {
        milestone_type: "insurance_renewal",
        due_date: "2025-06-15",
        description: "Renew policy",
        recurring: "1",
        recurrence_interval: "annual"
      }
    )

    assert_equal "insurance_renewal", updated.first["milestone_type"]
    assert_equal "2025-06-15", updated.first["due_date"]
    assert_equal "Renew policy", updated.first["description"]
    assert_equal true, updated.first["recurring"]
    assert_equal "annual", updated.first["recurrence_interval"]
  end

  test "remove deletes a milestone by index" do
    editor = ReviewMilestoneArrayEditor.new(
      [
        { milestone_type: "custom", due_date: "2025-05-01", description: "One", recurring: false },
        { milestone_type: "insurance_renewal", due_date: "2025-08-01", description: "Two", recurring: false }
      ].to_json
    )

    updated = editor.remove(index: 0)

    assert_equal 1, updated.length
    assert_equal "insurance_renewal", updated.first["milestone_type"]
  end

  test "raises for invalid milestone type" do
    editor = ReviewMilestoneArrayEditor.new(
      [ { milestone_type: "custom", due_date: "2025-05-01", description: "One", recurring: false } ].to_json
    )

    assert_raises(ReviewMilestoneArrayEditor::InvalidMilestonesError) do
      editor.update(index: 0, attrs: { milestone_type: "not_real", due_date: "2025-05-01" })
    end
  end

  test "raises for invalid index" do
    editor = ReviewMilestoneArrayEditor.new(
      [ { milestone_type: "custom", due_date: "2025-05-01", description: "One", recurring: false } ].to_json
    )

    assert_raises(ReviewMilestoneArrayEditor::InvalidMilestoneIndexError) do
      editor.remove(index: 2)
    end
  end

  test "raises for malformed JSON payload" do
    editor = ReviewMilestoneArrayEditor.new("not-json")

    assert_raises(ReviewMilestoneArrayEditor::InvalidMilestonesError) do
      editor.remove(index: 0)
    end
  end
end
