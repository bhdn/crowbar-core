provides "crowbar_ohai"

require_plugin "kernel"
require_plugin "dmi"
require_plugin "linux::s390x"

libvirt_uuid = nil

def convert(old)
   m = /(\h\h)(\h\h)(\h\h)(\h\h)-(\h\h)(\h\h)-(\h\h)(\h\h)-(\h{4})-(\h{12})/.match(old)
   [m[4] + m[3] + m[2] + m[1], m[6] + m[5], m[8] + m[7], m[9], m[10]].join("-").downcase
end

if kernel[:machine] == "s390x"
  if s390x[:system][:manufacturer] == "KVM"
    libvirt_uuid = s390x[:system][:uuid]
  end
else
  manufacturer = dmi[:system] ? dmi[:system][:manufacturer] : "unknown"
  if ["Bochs", "QEMU"].include? manufacturer
    libvirt_uuid = convert(dmi[:system][:uuid])
  end
end

crowbar_ohai[:libvirt] = {}
crowbar_ohai[:libvirt][:guest_uuid] = libvirt_uuid
