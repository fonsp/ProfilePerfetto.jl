module ProfilePerfetto

export @perfetto, @perfetto_open, @perfetto_view, perfetto_view, perfetto_open

import Profile
import JSON
import Base64
import Dates

include("sentinel.jl")
include("samples.jl")
include("gc.jl")
include("json.jl")
include("display.jl")
include("view.jl")
include("macro.jl")

function __init__()
    _gc_init_callbacks()
end

end # module
