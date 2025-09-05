defmodule RoomzCaldavToGenericConnectorWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  def render("invalid_datetime.json", %{reason: reason}) do
    %{errors: %{detail: "The given datetime was invalid: #{reason}"}}
  end

  def render("missing_datetimes_range.json", _assigns) do
    %{errors: %{detail: "The meetings range were missing."}}
  end

  def render("invalid_model.json", %{error: %{action: :required_fields} = error}) do
    %{message: message, fields: fields} = error

    %{
      title: message,
      errors: Enum.map(fields, fn x -> "The field #{Atom.to_string(x)} is missing." end)
    }
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
