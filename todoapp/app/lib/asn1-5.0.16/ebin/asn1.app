{application, asn1,
 [{description, "The Erlang ASN1 compiler version 5.0.16"},
  {vsn, "5.0.16"},
  {modules, [
        asn1rt_nif
             ]},
  {registered, [
	asn1_ns,
	asn1db
		]},
  {env, []},
  {applications, [kernel, stdlib]},
  {runtime_dependencies, ["stdlib-2.0","kernel-3.0","erts-7.0"]}
  ]}.
