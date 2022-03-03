# Copyright 2020 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

load("@io_bazel_rules_docker//container:providers.bzl", "PushInfo")
load(
    "@io_bazel_rules_docker//skylib:path.bzl",
    _get_runfile_path = "runfile",
)
load("//skylib:providers.bzl", "ImagePushesInfo")
load("//skylib/workspace:aspect.bzl", "pushable_aspect")

def _file_to_runfile(ctx, file):
    return file.owner.workspace_root or ctx.workspace_name + "/" + file.short_path

def _workspace_impl(ctx):
    transitive_executables = []
    transitive_runfiles = []
    transitive_data = []

    for t in ctx.attr.data:
        transitive_data.append(t[DefaultInfo].files)

    # flatten & 'uniquify' our list of asset files
    data = depset(transitive = transitive_data).to_list()

    runfiles = depset(transitive = transitive_runfiles).to_list()

    files = []

    tars = []
    for src in ctx.attr.srcs:
        tar = src.files.to_list()[0]
        tars.append(tar)

    rf = ctx.runfiles(files = runfiles + data + tars + ctx.files._bash_runfiles)

    trans_img_pushes = []
    if ctx.attr.push:
        trans_img_pushes = depset(transitive = [
            obj[ImagePushesInfo].image_pushes
            for obj in ctx.attr.srcs
            if ImagePushesInfo in obj
        ]).to_list()
        files += [obj.files_to_run.executable for obj in trans_img_pushes]

        for obj in trans_img_pushes:
            rf = rf.merge(obj[DefaultInfo].default_runfiles)

    ctx.actions.expand_template(
        template = ctx.file._template,
        substitutions = {
            "%{workspace_tar_targets}": " ".join([json.encode(_file_to_runfile(ctx, t)) for t in tars]),
            "%{push_targets}": " ".join([json.encode(_file_to_runfile(ctx, exe.files_to_run.executable)) for exe in trans_img_pushes]),
            # "async $(rlocation metered/%s)" % exe.files_to_run.executable.short_path
        },
        output = ctx.outputs.executable,
    )

    return [
        DefaultInfo(
            files = depset(files),
            runfiles = rf,
        ),
        ImagePushesInfo(
            image_pushes = depset(
                transitive = [
                    obj[ImagePushesInfo].image_pushes
                    for obj in ctx.attr.srcs
                    if ImagePushesInfo in obj
                ],
            ),
        ),
    ]

workspace = rule(
    implementation = _workspace_impl,
    attrs = {
        "srcs": attr.label_list(
            # cfg = "host",
            # allow_files = True,
            aspects = [pushable_aspect],
        ),
        "push": attr.bool(default = True),
        "data": attr.label_list(
            # cfg = "host",
            allow_files = True,
        ),
        "_template": attr.label(
            default = Label("//skylib/workspace:workspace.sh.tpl"),
            allow_single_file = True,
        ),
        "_bash_runfiles": attr.label(
            allow_files = True,
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
    executable = True,
)
