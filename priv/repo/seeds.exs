# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Langler.Repo.insert!(%Langler.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Langler.Accounts.User
alias Langler.Repo
import Ecto.Query

# Set the first user (by ID) as admin
# You can also set specific users by email by uncommenting and modifying the email-based section below

first_user = Repo.one(from u in User, order_by: [asc: u.id], limit: 1)

if first_user do
  first_user
  |> User.changeset(%{is_admin: true})
  |> Repo.update!()

  IO.puts("✓ Set first user (#{first_user.email}) as admin")
else
  IO.puts("⚠ No users found in database")
end

# Alternative: Set specific users by email as admin
# Uncomment and modify the emails below to set specific users as admin
#
# admin_emails = ["admin@example.com", "chase.gilliam@gmail.com"]
#
# Enum.each(admin_emails, fn email ->
#   case Langler.Accounts.get_user_by_email(email) do
#     nil ->
#       IO.puts("⚠ User with email #{email} not found")
#
#     user ->
#       user
#       |> User.changeset(%{is_admin: true})
#       |> Repo.update!()
#
#       IO.puts("✓ Set #{email} as admin")
#   end
# end)
