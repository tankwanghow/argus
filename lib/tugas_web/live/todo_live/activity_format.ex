defmodule TugasWeb.TodoLive.ActivityFormat do
  @moduledoc false

  def display_name(%{username: u}) when is_binary(u) and u != "", do: u
  def display_name(%{email: e}) when is_binary(e), do: e
  def display_name(_), do: "Unknown"

  def audit_action_label("created"), do: "Created"
  def audit_action_label("updated"), do: "Updated"
  def audit_action_label("completed"), do: "Completed"
  def audit_action_label("reopened"), do: "Reopened"
  def audit_action_label("deleted"), do: "Deleted"
  def audit_action_label("canceled"), do: "Canceled"
  def audit_action_label("escalated"), do: "Escalated"
  def audit_action_label(other), do: other

  def activity_subject(%{action: action, old_value: title})
      when action in ["deleted", "canceled"] and is_binary(title),
      do: " \"#{title}\""

  def activity_subject(%{todo: %{title: title}}) when is_binary(title), do: " \"#{title}\""
  def activity_subject(_), do: ""

  def format_time(%DateTime{} = dt, timezone) do
    TugasWeb.CoreComponents.format_datetime(dt, timezone, :short)
  end

  def format_time(_, _), do: ""
end
