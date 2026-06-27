defmodule TugasWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use TugasWeb, :html

  embed_templates "page_html/*"

  @doc false
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true

  def feature(assigns) do
    ~H"""
    <div class="rounded-2xl border b-line bg-surface p-7 tugas-feature-card transition-all">
      <div class="size-11 rounded-xl bg-teal-soft border b-teal-soft grid place-items-center">
        <.icon name={@icon} class="size-5 c-teal" />
      </div>
      <h3 class="font-display text-xl text-ink mt-5">{@title}</h3>
      <p class="c-muted text-sm leading-relaxed mt-2">{@body}</p>
    </div>
    """
  end
end
