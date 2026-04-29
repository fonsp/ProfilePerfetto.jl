"""
    perfetto_view(data = Profile.fetch(; include_meta = false),
                         lidict = Profile.getdict(data);
                         name = "Julia profile")

Converts Julia profile sample data to an embedded [Perfetto](https://ui.perfetto.dev)
trace viewer. Returns a [`PerfettoDisplay`](@ref) that renders as an interactive
trace when displayed in a Pluto, VS Code or Jupyter notebook cell.

See also: [`@perfetto`](@ref), [`perfetto_open`](@ref).
"""
function perfetto_view(
    data::Vector{UInt64} = Profile.fetch(; include_meta = true),
    lidict = Profile.getdict(data);
    name::String = _default_name(),
    filter_sentinel::Bool = false,
    wall_time_ns::Union{Nothing,UInt64} = nothing,
)
    json_contents = _samples_to_perfetto_json(
        data,
        lidict;
        sample_interval_us = _profile_delay_us(),
        filter_sentinel,
        wall_time_ns,
    )
    b64 = Base64.base64encode(json_contents)
    id = String(rand('a':'z', 10))
    html = """
        <div style="
          width: 100%; 
          height: clamp(650px, 90vh, 1000px);     
          position: relative;
          ">
        <iframe id="$id" src="https://ui.perfetto.dev"
          style="width:100%;height:100%;border:7px solid yellow;border-radius: 12px; box-sizing: border-box;"></iframe>
        
          $(_overlay_html())
        
        <script>
        const b64 = "$b64";
        const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
        const iframe = document.getElementById('$id');
        const overlay = document.getElementById('overlay');

        const interval = setInterval(() => {
          iframe.contentWindow.postMessage('PING', 'https://ui.perfetto.dev');
        }, 50);

        window.addEventListener('message', (e) => {
          if (e.data !== 'PONG') return;
          clearInterval(interval);
          iframe.contentWindow.postMessage({
            perfetto: {
              buffer: bytes.buffer,
              title: "$(name)",
            }
          }, 'https://ui.perfetto.dev');
          setTimeout(() => {
            overlay.style.opacity = '0';
            setTimeout(() => overlay.remove(), 400);
          }, 300);
        });
        </script>
        </div>"""
    return PerfettoDisplay(html)
end

"""
    perfetto_open(data = Profile.fetch(; include_meta = false),
                         lidict = Profile.getdict(data);
                         name = "Julia profile")

Opens the current Julia profile in the default web browser using the
[Perfetto](https://ui.perfetto.dev) trace viewer. Returns the path to the
temporary HTML file that was opened.
"""
function perfetto_open(
    data::Vector{UInt64} = Profile.fetch(; include_meta = true),
    lidict = Profile.getdict(data);
    name::String = _default_name(),
    filter_sentinel::Bool = false,
    wall_time_ns::Union{Nothing,UInt64} = nothing,
)
    json_contents = _samples_to_perfetto_json(
        data,
        lidict;
        sample_interval_us = _profile_delay_us(),
        filter_sentinel,
        wall_time_ns,
    )
    b64 = Base64.base64encode(json_contents)
    html = """<!DOCTYPE html><html><body style="margin:0">
        <iframe id="pf" src="https://ui.perfetto.dev"
          style="width:100vw;height:100vh;border:none;position:fixed;top:0;left:0"></iframe>
        $(_overlay_html())
        <script>
        const b64 = "$b64";
        const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
        const iframe = document.getElementById('pf');
        const overlay = document.getElementById('overlay');

        const interval = setInterval(() => {
          iframe.contentWindow.postMessage('PING', 'https://ui.perfetto.dev');
        }, 50);

        window.addEventListener('message', (e) => {
          if (e.data !== 'PONG') return;
          clearInterval(interval);
          iframe.contentWindow.postMessage({
            perfetto: {
              buffer: bytes.buffer,
              title: "$(name)",
            }
          }, 'https://ui.perfetto.dev');
          setTimeout(() => {
            overlay.style.opacity = '0';
            setTimeout(() => overlay.remove(), 400);
          }, 300);
        });
        </script>
        </body></html>"""
    filename = tempname(; cleanup = false) * ".html"
    write(filename, html)
    if Sys.isapple()
        run(`open $filename`)
    elseif Sys.iswindows()
        run(`cmd /c start "" $filename`)
    elseif Sys.islinux()
        run(`xdg-open $filename`)
    else
        @info "Open this in your browser: $filename"
    end
    return filename
end
