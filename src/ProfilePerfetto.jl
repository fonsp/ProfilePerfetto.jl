module ProfilePerfetto

export @perfetto, @perfetto_open, @perfetto_view, perfetto_view, perfetto_open,
    @autoperfetto, @autoperfetto_open, @autoperfetto_view

import Profile
import JSON
import Base64
import Dates

include("sentinel.jl")
include("samples.jl")
include("json.jl")
include("display.jl")
include("view.jl")
include("macro.jl")
include("autocalibrate.jl")

end # module
