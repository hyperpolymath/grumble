# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Mailer — Email delivery via Swoosh.
#
# Configured per environment:
#   dev:  Swoosh.Adapters.Local (preview at /dev/mailbox)
#   test: Swoosh.Adapters.Test
#   prod: Swoosh.Adapters.SMTP (or Postmark/Sendgrid via env vars)

defmodule Burble.Mailer do
  use Swoosh.Mailer, otp_app: :burble
end

defmodule Burble.Email do
  @moduledoc """
  Email templates for Burble.
  """

  import Swoosh.Email

  @from {"Burble", "noreply@burble.local"}

  @doc """
  Magic link email for passwordless login.

  The link contains a token that expires in 15 minutes.
  """
  def magic_link(to_email, token, base_url \\ "http://localhost:6473") do
    link = "#{base_url}/auth/magic?token=#{token}"

    new()
    |> to(to_email)
    |> from(@from)
    |> subject("Sign in to Burble")
    |> text_body("""
    Click to sign in to Burble:

    #{link}

    This link expires in 15 minutes.
    If you didn't request this, ignore this email.
    """)
    |> html_body("""
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; padding: 24px;">
      <h2 style="color: #1a1a1a;">Sign in to Burble</h2>
      <p>Click the button below to sign in:</p>
      <a href="#{link}" style="display: inline-block; background: #4f46e5; color: white;
         padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: bold;">
        Sign In
      </a>
      <p style="color: #666; font-size: 14px; margin-top: 24px;">
        This link expires in 15 minutes.
        If you didn't request this, ignore this email.
      </p>
    </div>
    """)
  end
end
