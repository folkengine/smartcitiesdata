defmodule Andi.InputSchemas.DisplayNames do
  @moduledoc false

  @display_names %{
    id: "ID",
    contactEmail: "Maintainer Email",
    contactName: "Maintainer Name",
    dataTitle: "Dataset Title",
    description: "Description",
    homepage: "Data Homepage URL",
    issuedDate: "Release Date",
    keywords: "Keywords",
    language: "Language",
    license: "License",
    modifiedDate: "Last Updated",
    orgTitle: "Organization",
    publishFrequency: "Update Frequency",
    spatial: "Spatial Boundaries",
    temporal: "Temporal Boundaries",
    dataName: "Data Name",
    orgName: "Organization Name",
    private: "Level of Access",
    schema: "Schema",
    sourceFormat: "Source Format",
    sourceType: "Source Type",
    sourceUrl: "Source Url",
    topLevelSelector: "Top Level Selector"
  }

  def get(field_key) do
    Map.get(@display_names, field_key)
  end
end
