module ProfilePerfetto

export @perfetto, @perfetto_open, @perfetto_view, perfetto_view, perfetto_open

import Profile
import JSON
import Base64
import Dates

include("sentinel.jl")
include("samples.jl")
include("json.jl")
include("display.jl")
include("view.jl")
include("autocalibrate.jl")
include("macro.jl")

end # module
