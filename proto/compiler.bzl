# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load(
    "@io_bazel_rules_go//go:def.bzl",
    "GoLibrary",
    "go_context",
)
load(
    "@io_bazel_rules_go//go/private:common.bzl",  # TODO: @skylib?
    "sets",
)
load(
    "@io_bazel_rules_go//go/private:rules/rule.bzl",
    "go_rule",
)

GoProtoCompiler = provider()

def go_proto_compile(go, compiler, proto, imports, importpath):
    go_srcs = []
    outpath = None
    for src in proto.direct_sources:
        out = go.declare_file(go, path = importpath + "/" + src.basename[:-len(".proto")], ext = compiler.suffix)
        go_srcs.append(out)
        if outpath == None:
            outpath = out.dirname[:-len(importpath)]
    args = go.actions.args()
    args.add_all([
        "--protoc",
        compiler.protoc,
        "--importpath",
        importpath,
        "--out_path",
        outpath,
        "--plugin",
        compiler.plugin,
        "--compiler_path",
        go.cgo_tools.compiler_path,
    ])
    args.add_all(compiler.options, before_each = "--option")
    if compiler.import_path_option:
        args.add_all([importpath], before_each = "--option", format_each = "import_path=%s")
    args.add_all(proto.transitive_descriptor_sets, before_each = "--descriptor_set")
    args.add_all(go_srcs, before_each = "--expected")
    args.add_all(imports, before_each = "--import")
    args.add_all(proto.direct_sources, map_each = proto_path)
    go.actions.run(
        inputs = sets.union([
            compiler.go_protoc,
            compiler.protoc,
            compiler.plugin,
        ], proto.transitive_descriptor_sets),
        outputs = go_srcs,
        progress_message = "Generating into %s" % go_srcs[0].dirname,
        mnemonic = "GoProtocGen",
        executable = compiler.go_protoc,
        arguments = [args],
    )
    return go_srcs

def proto_path(proto):
    """
    The proto path is not really a file path
    It's the path to the proto that was seen when the descriptor file was generated.
    """
    path = proto.path
    root = proto.root.path
    ws = proto.owner.workspace_root
    if path.startswith(root):
        path = path[len(root):]
    if path.startswith("/"):
        path = path[1:]
    if path.startswith(ws):
        path = path[len(ws):]
    if path.startswith("/"):
        path = path[1:]
    return path

def _go_proto_compiler_impl(ctx):
    go = go_context(ctx)
    library = go.new_library(go)
    source = go.library_to_source(go, ctx.attr, library, ctx.coverage_instrumented())
    return [
        GoProtoCompiler(
            deps = ctx.attr.deps,
            compile = go_proto_compile,
            options = ctx.attr.options,
            suffix = ctx.attr.suffix,
            go_protoc = ctx.executable._go_protoc,
            protoc = ctx.executable._protoc,
            plugin = ctx.executable.plugin,
            valid_archive = ctx.attr.valid_archive,
            import_path_option = ctx.attr.import_path_option,
        ),
        library,
        source,
    ]

go_proto_compiler = go_rule(
    _go_proto_compiler_impl,
    attrs = {
        "deps": attr.label_list(providers = [GoLibrary]),
        "options": attr.string_list(),
        "suffix": attr.string(default = ".pb.go"),
        "valid_archive": attr.bool(default = True),
        "import_path_option": attr.bool(default = True),
        "plugin": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "host",
            default = "@com_github_golang_protobuf//protoc-gen-go",
        ),
        "_go_protoc": attr.label(
            executable = True,
            cfg = "host",
            default = "@io_bazel_rules_go//go/tools/builders:go-protoc",
        ),
        "_protoc": attr.label(
            executable = True,
            cfg = "host",
            default = "@com_google_protobuf//:protoc",
        ),
    },
)
