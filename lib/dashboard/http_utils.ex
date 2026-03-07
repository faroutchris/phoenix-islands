defmodule Dashboard.HttpUtils do
  def matching_headers?(header1, header2) do
    not is_nil(header2) and header1 == header2
  end

  def make_headers(%{} = headers, name, value) do
    if value != nil do
      Map.put(headers, name, value)
    else
      headers
    end
  end

  def extract_header(header_name, %HTTPoison.Response{} = response) do
    response.headers
    |> Enum.map(fn {header, value} ->
      {String.downcase(header, :default), value}
    end)
    |> Enum.into(%{})
    |> Map.get(header_name)
  end
end
