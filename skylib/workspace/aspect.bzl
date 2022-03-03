load("//skylib:providers.bzl", "ImagePushesInfo")
load("@io_bazel_rules_docker//container:providers.bzl", "PushInfo")

def _pushable_aspect_impl(target, ctx):
    """
    """
    image_pushes = []
    transitive_image_pushes = []

    if ImagePushesInfo in target:
        image_pushes += target[ImagePushesInfo].image_pushes.to_list()
    elif PushInfo in target:
        image_pushes += [target]

    for attr in dir(ctx.rule.attr):
        if attr in ["to_json", "to_proto"] or attr.startswith("_"):
            continue  # skip non-attrs and private attrs
        attr_targets = []  # collect all targets referenced by the current attr
        value = getattr(ctx.rule.attr, attr)
        value_type = type(value)
        if value_type == "Target":
            attr_targets.append(value)
        elif value_type == "list":
            for item in value:
                if type(item) == "Target":
                    attr_targets.append(item)
        elif value_type == "dict":
            for k, v in value.items():
                if type(k) == "Target":
                    attr_targets.append(k)
                if type(v) == "Target":
                    attr_targets.append(v)
        for t in attr_targets:
            if ImagePushesInfo in t:
                transitive_image_pushes += [t[ImagePushesInfo].image_pushes]

    if image_pushes or transitive_image_pushes:
        return [
            ImagePushesInfo(
                image_pushes = depset(
                    image_pushes,
                    transitive = transitive_image_pushes,
                ),
            ),
        ]
    else:
        return []

pushable_aspect = aspect(
    implementation = _pushable_aspect_impl,
    attr_aspects = ["*"],
)
