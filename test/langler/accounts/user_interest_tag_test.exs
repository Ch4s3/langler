defmodule Langler.Accounts.UserInterestTagTest do
  use Langler.DataCase, async: true

  alias Langler.Accounts.UserInterestTag

  describe "changeset/2" do
    test "builds a valid changeset when all fields are supplied" do
      attrs = %{user_id: 1, tag: "spanish", language: "spanish"}

      changeset = UserInterestTag.changeset(%UserInterestTag{}, attrs)

      assert changeset.valid?
    end

    test "requires user_id and tag" do
      changeset = UserInterestTag.changeset(%UserInterestTag{}, %{})

      assert %{
               user_id: ["can't be blank"],
               tag: ["can't be blank"]
             } = errors_on(changeset)

      # language has a default value so it's not required
      refute Map.has_key?(errors_on(changeset), :language)
    end

    test "requires language when explicitly set to nil" do
      changeset =
        UserInterestTag.changeset(%UserInterestTag{}, %{
          user_id: 1,
          tag: "spanish",
          language: nil
        })

      assert %{language: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
