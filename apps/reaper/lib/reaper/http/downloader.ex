defmodule Reaper.Http.Downloader do
  @moduledoc """
  Will download large files over http to a file on disk.
  """
  require Logger

  @type url :: String.t()
  @type headers :: list()
  @type reason :: term()

  defmodule InvalidStatusError do
    defexception [:message, :status]
  end

  defmodule IdleTimeoutError do
    defexception [:message, :timeout]
  end

  defmodule HttpDownloadError do
    defexception [:message]
  end

  defmodule Response do
    @moduledoc false
    defstruct status: nil,
              headers: nil,
              request_ref: nil,
              conn: nil,
              destination: nil,
              done: false,
              url: nil
  end

  @doc """
  Downloads file at url to specified location on disk

  Options:

  * `:to` - path to file to write data from request. **REQUIRED**
  * `:connect_timeout` - amount of time to wait for a network connection to be established. (default 30_000)
  * `:idle_timeout` - amount of time to wait to receive next chunk for server. (default :infinity)

  ##Example

     iex>Reaper.Http.Downloader.download("http://some.url/file.txt", to: "a-file-on-disk.txt")

  """
  @spec download(url(), headers(), keyword()) ::
          {:ok, %Response{}} | {:error, reason()} | no_return()
  def download(url, headers \\ [], opts) do
    uri = URI.parse(url)
    body = Keyword.get(opts, :body, "")

    evaluated_headers =
      evaluate_headers(headers)
      |> add_content_type(body)

    action = Keyword.get(opts, :action, "GET") |> String.upcase()

    with {:ok, conn} <- connect(uri, opts),
         {:ok, conn, request_ref} <- request(conn, action, uri, evaluated_headers, body),
         {:ok, response} <- create_initial_response(conn, request_ref, url, opts),
         {:ok, file} <- File.open(response.destination, [:write, :delayed_write]),
         {:ok, response} <- stream_responses({response, file}, opts),
         {:ok, response} <- close_conn(response) do
      File.close(file)
      handle_status(response, evaluated_headers)
    else
      {:error, conn, error} ->
        Mint.HTTP.close(conn)
        raise error

      error ->
        raise HttpDownloadError, message: "Error downloading file from #{url}: #{inspect(error)}"
    end
  end

  defp connect(uri, opts) do
    scheme = String.to_atom(uri.scheme)
    connect_timeout = Keyword.get(opts, :connect_timeout, 30_000)
    protocol = format_protocol(Keyword.get(opts, :protocol, nil))

    case protocol do
      nil ->
        Mint.HTTP.connect(scheme, uri.host, uri.port, transport_opts: [timeout: connect_timeout])

      protocol ->
        Mint.HTTP.connect(scheme, uri.host, uri.port,
          transport_opts: [timeout: connect_timeout],
          protocols: protocol
        )
    end
  end

  defp format_protocol(protocol) when protocol == nil, do: nil

  defp format_protocol(protocol) when is_list(protocol) do
    Enum.map(protocol, &String.to_atom/1)
  end

  defp request(conn, method, uri, headers, body \\ "") do
    Mint.HTTP.request(conn, method, "#{uri.path}?#{uri.query}", headers, body)
  end

  defp create_initial_response(conn, request_ref, url, opts) do
    {:ok,
     %Response{
       conn: conn,
       request_ref: request_ref,
       url: url,
       destination: Keyword.get(opts, :to)
     }}
  end

  defp stream_responses({%Response{done: true} = response, _file}, _opts) do
    {:ok, response}
  end

  defp stream_responses({response, file}, opts) do
    idle_timeout = Keyword.get(opts, :idle_timeout, :infinity)

    case receive_message(response, idle_timeout) do
      {:ok, conn, http_messages} ->
        http_messages
        |> Enum.reduce({%{response | conn: conn}, file}, &handle_http_message/2)
        |> stream_responses(opts)

      {:error, reason} ->
        {:error, response.conn, reason}

      {:error, conn, reason, _responses} ->
        {:error, conn, reason}
    end
  end

  defp receive_message(response, idle_timeout) do
    receive do
      message ->
        Mint.HTTP.stream(response.conn, message)
    after
      idle_timeout ->
        message = "Idle timeout was reached while attempting to download #{response.url}"
        {:error, IdleTimeoutError.exception(timeout: idle_timeout, message: message)}
    end
  end

  defp handle_http_message({:status, _request_ref, status_code}, {response, file}) do
    {%{response | status: status_code}, file}
  end

  defp handle_http_message({:headers, _request_ref, headers}, {response, file}) do
    {%{response | headers: headers}, file}
  end

  defp handle_http_message({:data, _request_ref, binary}, {response, file}) do
    IO.binwrite(file, binary)
    {response, file}
  end

  defp handle_http_message({:done, _request_ref}, {response, file}) do
    {%{response | done: true}, file}
  end

  defp handle_status(%Response{status: 200} = response, _headers) do
    {:ok, response}
  end

  defp handle_status(%Response{status: status} = response, headers) when status in [301, 302] do
    location = get_location(response.headers)
    Logger.info("Handling #{status} redirection from #{response.url} to #{location}")
    download(location, headers, to: response.destination)
  end

  defp handle_status(response, _headers) do
    Logger.warn(fn ->
      "Invalid Status Code returned while attempting to download file : #{inspect(response)}"
    end)

    {:error,
     InvalidStatusError.exception(
       status: response.status,
       message: "Invalid status code: #{response.status}"
     )}
  end

  defp get_location(headers) do
    headers
    |> Enum.find_value(fn {key, value} -> key == "location" && value end)
  end

  defp close_conn(response) do
    {:ok, %{response | conn: Mint.HTTP.close(response.conn)}}
  end

  defp evaluate_headers(headers) do
    headers
    |> Enum.map(&evaluate_header(&1))
  end

  defp evaluate_header({key, value}) do
    {to_string(key), EEx.eval_string(value, [])}
  end

  # Right now we assume any body sent in a request will be json encoded.  We may change this in the future but
  # at this time we dont have any use cases to do otherwise
  defp add_content_type(headers, ""), do: headers
  defp add_content_type(headers, _body), do: [{"Content-Type", "application/json"} | headers]
end
