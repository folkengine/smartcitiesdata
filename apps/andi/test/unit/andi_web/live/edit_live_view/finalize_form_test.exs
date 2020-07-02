defmodule AndiWeb.EditLiveView.FinalizeFormTest do
  use ExUnit.Case

  import Checkov

  alias AndiWeb.EditLiveView.FinalizeForm

  import AndiWeb.Test.CronTestHelpers, only: [
    finalize_form: 0,
    finalize_form: 1,
    cronlist: 1,
    blank_cronlist: 0,
    future_hour: 0,
    future_day: 0,
    future_month: 0,
    future_year: 0,
  ]


  data_test "converts finalize form data to cadence in form data for #{case}" do
    form_data = FinalizeForm.update_form_with_schedule(finalize_form_data, %{"technical" => %{}})
    assert expected_form_data == form_data

    where([
      [:case, :finalize_form_data, :expected_form_data],
      ["once", finalize_form(), %{"technical" => %{"cadence" => "once"}}],
      ["never", finalize_form(%{"cadence_type" => "never"}), %{"technical" => %{"cadence" => "never"}}],
      ["empty", finalize_form(%{"cadence_type" => ""}), %{"technical" => %{}}],
      ["nil", finalize_form(%{"cadence_type" => nil}), %{"technical" => %{}}],
      ["repeating", finalize_form(%{"cadence_type" => "repeating"}), %{"technical" => %{"cadence" => "* * * * * *"}}],
      ["repeating with seconds", finalize_form(%{"cadence_type" => "repeating", "repeating_schedule" => cronlist(%{"second" => 0})}), %{"technical" => %{"cadence" => "0 * * * * *"}}],
      ["repeating with year", finalize_form(%{"cadence_type" => "repeating", "repeating_schedule" => cronlist(%{"year" => "*"})}), %{"technical" => %{"cadence" => "0 * * * * * *"}}],
      ["future", finalize_form(%{"cadence_type" => "future"}), %{"technical" => %{"cadence" => "0 0 #{future_hour()} #{future_day()} #{future_month()} * #{future_year()}"}}],
      ["future with invalid date and time", finalize_form(%{"cadence_type" => "future", "future_schedule" => %{"date" => "", "time" => ""}}), %{"technical" => %{"cadence" => ""}}],
      ["future with invalid date", finalize_form(%{"cadence_type" => "future", "future_schedule" => %{"date" => ""}}), %{"technical" => %{"cadence" => ""}}],
      ["future with invalid time", finalize_form(%{"cadence_type" => "future", "future_schedule" => %{"time" => ""}}), %{"technical" => %{"cadence" => ""}}],
      ["future with invalid repeating schedule", finalize_form(%{"cadence_type" => "future", "repeating_schedule" => blank_cronlist()}), %{"technical" => %{"cadence" => "0 0 #{future_hour()} #{future_day()} #{future_month()} * #{future_year()}"}}],
      ["future with short time", finalize_form(%{"cadence_type" => "future", "future_schedule" => %{"time" => "00:00"}}), %{"technical" => %{"cadence" => "0 0 #{future_hour()} #{future_day()} #{future_month()} * #{future_year()}"}}],
      ["completly missing future schedule", finalize_form(%{"cadence_type" => "future", "future_schedule" => nil}), %{"technical" => %{"cadence" => ""}}],
      ["future with missing fields", finalize_form(%{"cadence_type" => "future", "future_schedule" => %{}}), %{"technical" => %{"cadence" => ""}}],
    ])
  end
end