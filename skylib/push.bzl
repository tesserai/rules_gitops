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
"""An implementation of container_push based on google/go-containerregistry.
This wraps the rules_docker.container.go.cmd.pusher.pusher executable in a
Bazel rule for publishing images.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@io_bazel_rules_docker//container:providers.bzl", "PushInfo")
load("//skylib:providers.bzl", _K8sPushInfo = "PushInfo")
load(
    "@io_bazel_rules_docker//container:layer_tools.bzl",
    _gen_img_args = "generate_args_for_image",
    _get_layers = "get_from_target",
    _layer_tools = "tools",
)
load(
    "@io_bazel_rules_docker//skylib:path.bzl",
    "runfile",
)

K8sPushInfo = _K8sPushInfo

def _get_runfile_path(ctx, f):
    return "${RUNFILES}/%s" % runfile(ctx, f)

def _impl(ctx):
    """Core implementation of container_push."""

    # TODO: Possible optimization for efficiently pushing intermediate format after container_image is refactored, similar with the old python implementation, e.g., push-by-layer.

    pusher_args = []
    pusher_input = []
    digester_args = []
    digester_input = []

    # Parse and get destination registry to be pushed to
    registry = ctx.expand_make_variables("registry", ctx.attr.registry, {})
    repository = ctx.expand_make_variables("repository", ctx.attr.repository, {})
    if not repository:
        repository = ctx.attr.image.label.package.lstrip("/") + "/" + ctx.attr.image.label.name
    prefix = ctx.attr.repository_prefix
    if prefix and prefix != repository.partition("/")[0]:  # don't add prefix if repository already starts w/ it
        repository = "%s/%s" % (prefix, repository)
    tag = ctx.expand_make_variables("tag", ctx.attr.tag, {})

    # If a tag file is provided, override <tag> with tag value
    if ctx.file.tag_file:
        tag = "$(cat {})".format(_get_runfile_path(ctx, ctx.file.tag_file))
        pusher_input.append(ctx.file.tag_file)

    stamp = "{" in tag or "{" in registry or "{" in repository
    stamp_inputs = [ctx.file._info_file] if stamp else []
    for f in stamp_inputs:
        pusher_args += ["-stamp-info-file", "%s" % _get_runfile_path(ctx, f)]
    pusher_input += stamp_inputs

    # Construct container_parts for input to pusher.
    image = _get_layers(ctx, ctx.label.name, ctx.attr.image)
    pusher_img_args, pusher_img_inputs = _gen_img_args(ctx, image, _get_runfile_path)
    pusher_args += pusher_img_args
    pusher_input += pusher_img_inputs
    digester_img_args, digester_img_inputs = _gen_img_args(ctx, image)
    digester_input += digester_img_inputs
    digester_args += digester_img_args
    pusher_runfiles = [ctx.executable._pusher] + pusher_input

    if ctx.attr.skip_unchanged_digest:
        pusher_args += ["-skip-unchanged-digest"]
    digester_args += ["--dst", str(ctx.outputs.digest.path), "--format", str(ctx.attr.format)]
    ctx.actions.run(
        inputs = digester_input,
        outputs = [ctx.outputs.digest],
        executable = ctx.executable._digester,
        arguments = digester_args,
        tools = ctx.attr._digester[DefaultInfo].default_runfiles.files,
        mnemonic = "ContainerPushDigest",
    )

    if ctx.attr.image_digest_tag:
        tag = "$(cat {} | cut -d ':' -f 2 | cut -c 1-7)".format(_get_runfile_path(ctx, ctx.outputs.digest))
        pusher_runfiles += [ctx.outputs.digest]

    pusher_args.append("--format={}".format(ctx.attr.format))
    pusher_args.append("--dst={registry}/{repository}:{tag}".format(
        registry = registry,
        repository = repository,
        tag = tag,
    ))

    # If the docker toolchain is configured to use a custom client config
    # directory, use that instead
    toolchain_info = ctx.toolchains["@io_bazel_rules_docker//toolchains/docker:toolchain_type"].info
    if toolchain_info.client_config != "":
        pusher_args += ["-client-config-dir", str(toolchain_info.client_config)]

    ctx.actions.expand_template(
        template = ctx.file._tag_tpl,
        substitutions = {
            "%{args}": " ".join(pusher_args),
            "%{container_pusher}": _get_runfile_path(ctx, ctx.executable._pusher),
        },
        output = ctx.outputs.executable,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = pusher_runfiles)
    runfiles = runfiles.merge(ctx.attr._pusher[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            executable = ctx.outputs.executable,
            runfiles = runfiles,
        ),
        PushInfo(
            registry = registry,
            repository = repository,
            tag = tag,
            stamp_inputs = stamp_inputs,
            digest = image["digest"],
        ),
        K8sPushInfo(
            image_label = ctx.attr.image.label,
            legacy_image_name = ctx.attr.legacy_image_name,
            registry = registry,
            repository = repository,
            digestfile = image["digest"],
        ),
    ]

# Pushes a container image to a registry.
k8s_container_push = rule(
    doc = """
Pushes a container image.

This rule pushes a container image to a registry.

Args:
  name: name of the rule
  image: the label of the image to push.
  format: The form to push: Docker or OCI.
  legacy_image_name: alias for the image name in addition to default full bazel target name. Please use only for compatibility with older deployment
  registry: the registry to which we are pushing.
  repository: the name of the image. If not present, default to the image's bazel target path
  repository_prefix: an optional prefix added to the name of the image
  tag: (optional) the tag of the image, default to 'latest'.
""",
    attrs = dicts.add({
        "format": attr.string(
            default = "Docker",
            values = [
                "OCI",
                "Docker",
            ],
            doc = "The form to push: Docker or OCI, default to 'Docker'.",
        ),
        "image": attr.label(
            allow_single_file = [".tar"],
            mandatory = True,
            doc = "The label of the image to push.",
        ),
        "image_digest_tag": attr.bool(
            default = False,
            mandatory = False,
            doc = "Tag the image with the container digest, default to False",
        ),
        "legacy_image_name": attr.string(doc = "image name used in deployments, for compatibility with k8s_deploy. Do not use, refer images by full bazel target name instead"),
        "registry": attr.string(
            doc = "The registry to which we are pushing.",
            default = "docker.io",
        ),
        "repository": attr.string(
            doc = "the name of the image. If not present, default to the image's bazel target path",
        ),
        "repository_prefix": attr.string(
            doc = "an optional prefix added to the name of the image",
        ),
        "skip_unchanged_digest": attr.bool(
            default = False,
            doc = "Only push images if the digest has changed, default to False",
        ),
        "stamp": attr.bool(
            default = False,
            mandatory = False,
            doc = "(unused)",
        ),
        "tag": attr.string(
            default = "latest",
            doc = "(optional) The tag of the image, default to 'latest'.",
        ),
        "tag_file": attr.label(
            allow_single_file = True,
            doc = "(optional) The label of the file with tag value. Overrides 'tag'.",
        ),
        "_info_file": attr.label(
            default = Label("//skylib:more_stable_status.txt"),
            allow_single_file = True,
        ),
        "_digester": attr.label(
            default = "@io_bazel_rules_docker//container/go/cmd/digester",
            cfg = "host",
            executable = True,
        ),
        "_pusher": attr.label(
            default = "@io_bazel_rules_docker//container/go/cmd/pusher",
            cfg = "host",
            executable = True,
            allow_files = True,
        ),
        "_tag_tpl": attr.label(
            default = Label("//skylib:push-tag.sh.tpl"),
            allow_single_file = True,
        ),
    }, _layer_tools),
    executable = True,
    toolchains = ["@io_bazel_rules_docker//toolchains/docker:toolchain_type"],
    implementation = _impl,
    outputs = {
        "digest": "%{name}.digest",
    },
)
