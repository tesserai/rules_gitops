# Copyright 2020 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

load("//skylib:providers.bzl", "ImagePushesInfo")

def _file_to_runfile(ctx, file):
    return file.owner.workspace_root or ctx.workspace_name + "/" + file.short_path

def _gitops_impl(ctx):
    outputs = []

    if ctx.attr.render_snapshot:
        snapshot_dir = ctx.actions.declare_directory(ctx.attr.render_snapshot)

        outputs += [snapshot_dir]
        ctx.actions.run(
            executable = ctx.executable.workspace,
            arguments = [
                "--render",
                "{base}/{gitops_path}/{prefix}".format(
                    gitops_path = ctx.attr.gitops_path,
                    prefix = ctx.attr.prefix,
                    base = snapshot_dir.path,
                ),
            ],
            tools = [ctx.attr.workspace.files_to_run],
            outputs = outputs,
            mnemonic = "RenderWorkspace",
        )

    ctx.actions.expand_template(
        template = ctx.file._template,
        substitutions = {
            "%{target_dir_prefix}": "%s/%s" % (ctx.attr.gitops_path, ctx.attr.prefix),
            "%{workspace_target}": _file_to_runfile(ctx, ctx.executable.workspace),
        },
        output = ctx.outputs.executable,
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset(outputs),
            runfiles = ctx.runfiles(
                transitive_files = depset(transitive = [ctx.attr.workspace.default_runfiles.files]),
            ),
        ),
        ImagePushesInfo(
            image_pushes = depset(
                transitive = [ctx.attr.workspace[ImagePushesInfo].image_pushes],
            ),
        ),
    ]

gitops = rule(
    implementation = _gitops_impl,
    doc = """
    """,
    attrs = {
        "workspace": attr.label(
            cfg = "exec",
            executable = True,
            # allow_single_file = True,
        ),
        "deployment_branch": attr.string(),
        "gitops_path": attr.string(),
        "release_branch_prefix": attr.string(),
        "prefix": attr.string(),
        "render_snapshot": attr.string(),
        "_template": attr.label(
            default = Label("//skylib/workspace:gitops.sh.tpl"),
            allow_single_file = True,
        ),
        "_bash_runfiles": attr.label(
            allow_files = True,
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
    executable = True,
)
