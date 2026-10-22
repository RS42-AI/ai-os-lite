#!/usr/bin/env python3
"""Provision and migrate the Vault Setup Kit project structure.

Fresh installs use ``scaffold`` for additive directory creation. Existing
instances use ``plan`` followed by an exact-token ``apply`` and can reverse an
applied migration with ``rollback``. No command edits note lifecycle fields or
instruction files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from typing import Any, Iterable
from urllib.parse import quote


KIT_ROOT = Path(__file__).resolve().parents[1]
PROFILE_PATH = KIT_ROOT / "structure" / "project-structure.json"
SKIP_PARTS = {".git", ".trash", ".vault-structure-backups", ".vault-structure-migrations"}
SKIP_FILES = {".vault-structure-preview.json"}
INSTRUCTION_NAMES = {"AGENTS.md", "CLAUDE.md"}


class StructureError(RuntimeError):
    pass


def load_profile() -> dict[str, Any]:
    with PROFILE_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def rel(path: Path, vault: Path) -> str:
    return path.relative_to(vault).as_posix()


def safe_path(vault: Path, relative: str) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise StructureError(f"path escapes vault: {relative}")
    current = vault
    for part in candidate.parts:
        current /= part
        if current.is_symlink():
            raise StructureError(f"symlink path is unsupported: {relative}")
    resolved = (vault / candidate).resolve()
    try:
        resolved.relative_to(vault.resolve())
    except ValueError as exc:
        raise StructureError(f"path escapes vault: {relative}") from exc
    return vault / candidate


def frontmatter_type(path: Path) -> str | None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return None
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.startswith("type:"):
            return line.partition(":")[2].strip().strip('"\'')
    return None


def is_project_dir(directory: Path, profile: dict[str, Any], project_name: str | None = None) -> bool:
    if not directory.is_dir() or directory.is_symlink():
        return False
    name = project_name or directory.name
    candidates = tuple(directory / pattern.format(project=name) for pattern in profile["project_hub_names"])
    return any(candidate.is_file() and frontmatter_type(candidate) == "project" for candidate in candidates)


def business_areas(vault: Path, profile: dict[str, Any]) -> list[Path]:
    root = vault / profile["business"]["projects_root"]
    if not root.is_dir() or root.is_symlink():
        return []
    return sorted((p for p in root.iterdir() if p.is_dir() and not p.is_symlink() and not p.name.startswith(".")), key=lambda p: p.name)


def project_dirs(vault: Path, profile: dict[str, Any]) -> list[Path]:
    found: set[Path] = set()
    for area in business_areas(vault, profile):
        for directory, subdirs, _files in os.walk(area):
            path = Path(directory)
            subdirs[:] = sorted(d for d in subdirs if not d.startswith(".") and d not in profile["required_project_containers"] and not (path / d).is_symlink())
            if path != area and is_project_dir(path, profile):
                found.add(path)
                subdirs[:] = []
    personal_root = vault / profile["personal"]["projects_root"]
    if personal_root.is_dir() and not personal_root.is_symlink():
        for directory, subdirs, _files in os.walk(personal_root):
            path = Path(directory)
            subdirs[:] = sorted(d for d in subdirs if not d.startswith(".") and d not in profile["required_project_containers"] and not (path / d).is_symlink())
            if path != personal_root and is_project_dir(path, profile):
                found.add(path)
                subdirs[:] = []
    return sorted(found, key=lambda p: rel(p, vault))


def legacy_personal_projects(vault: Path, profile: dict[str, Any]) -> tuple[list[Path], list[Path]]:
    personal = vault / "Personal"
    projects: list[Path] = []
    unknown: list[Path] = []
    if not personal.is_dir():
        return projects, unknown
    reserved = {"1. Goals", "2. Projects", "Tasks"}
    for child in sorted((p for p in personal.iterdir() if p.is_dir() and not p.is_symlink()), key=lambda p: p.name):
        if child.name in reserved or child.name.startswith("."):
            continue
        if is_project_dir(child, profile):
            projects.append(child)
        elif child.name != "Goals":
            unknown.append(child)
    return projects, unknown


def area_resource_root(vault: Path, area: Path) -> Path:
    """Preserve configured roots; sorting prefixes are not identities."""
    config_path = safe_path(vault, "system-settings/workspace-layout.json")
    mapping = {}
    if config_path.exists():
        try:
            config = json.loads(config_path.read_text())
            if config.get("schema_version") != 1:
                raise ValueError("unsupported schema_version")
            mapping = config.get("area_resource_roots", {})
            if not isinstance(mapping, dict):
                raise ValueError("area_resource_roots must be an object")
        except (ValueError, TypeError, AttributeError) as exc:
            raise StructureError(f"invalid workspace layout: {exc}") from exc
    explicit = mapping.get(area.name)
    if explicit is not None:
        if not isinstance(explicit, str) or len(Path(explicit).parts) < 2 or Path(explicit).parts[0] != "5. Resources":
            raise StructureError(f"invalid Resources destination for {area.name}")
        destination = safe_path(vault, explicit)
        if destination.exists() and not destination.is_dir():
            raise StructureError(f"Resources destination is not a directory: {explicit}")
        return destination
    clean = re.sub(r"^\d+\.\s*", "", area.name)
    roots = list(dict.fromkeys([safe_path(vault, "5. Resources/" + area.name), safe_path(vault, "5. Resources/" + clean)]))
    present = [root for root in roots if root.exists()]
    if any(not root.is_dir() for root in present) or len(present) > 1:
        raise StructureError(f"ambiguous Resources destination for {area.name}; configure workspace-layout.json")
    return present[0] if present else roots[-1]


def mkdir_candidates(vault: Path, profile: dict[str, Any], future_projects: Iterable[Path] = ()) -> list[str]:
    wanted: set[Path] = set()
    wanted.update({
        vault / profile["personal"]["projects_root"],
        vault / profile["personal"]["area_tasks"],
        vault / profile["personal"]["area_resources"],
    })
    if not any((vault / root).is_dir() for root in profile["personal"]["legacy_goals_roots"]):
        wanted.add(vault / profile["personal"]["goals_root"])
    for area in business_areas(vault, profile):
        wanted.add(vault / profile["business"]["area_tasks"].format(area=area.name))
        wanted.add(area_resource_root(vault, area))
    discovered = project_dirs(vault, profile)
    for project in [*discovered, *future_projects]:
        for container in profile["required_project_containers"]:
            wanted.add(project / container)
    return sorted((rel(path, vault) for path in wanted if not path.exists()))


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_digest(path: Path) -> str:
    digest = hashlib.sha256()
    for entry in sorted(path.rglob("*"), key=lambda p: p.relative_to(path).as_posix()):
        relative = entry.relative_to(path).as_posix()
        if any(part in SKIP_PARTS for part in entry.parts):
            continue
        if entry.is_symlink():
            digest.update(b"l\0")
            digest.update(relative.encode())
            digest.update(b"\0")
            digest.update(os.readlink(entry).encode())
            continue
        digest.update(("d\0" if entry.is_dir() else "f\0").encode())
        digest.update(relative.encode())
        digest.update(b"\0")
        if entry.is_file():
            digest.update(file_digest(entry).encode())
    return digest.hexdigest()


def source_digest(path: Path) -> str:
    return file_digest(path) if path.is_file() else tree_digest(path)


def add_replacements(replacements: list[dict[str, str]], source: str, target: str, include_stem: bool = False) -> None:
    pairs = [(source, target)]
    encoded_source = quote(source, safe="/")
    encoded_target = quote(target, safe="/")
    if encoded_source != source:
        pairs.append((encoded_source, encoded_target))
    if include_stem and source.endswith(".md") and target.endswith(".md"):
        pairs.append((source[:-3], target[:-3]))
        encoded_stem_source = quote(source[:-3], safe="/")
        encoded_stem_target = quote(target[:-3], safe="/")
        if encoded_stem_source != source[:-3]:
            pairs.append((encoded_stem_source, encoded_stem_target))
    for old, new in pairs:
        item = {"from": old, "to": new}
        if item not in replacements:
            replacements.append(item)


def bounded_bytes_pattern(value: str) -> re.Pattern[bytes]:
    return re.compile(re.escape(value.encode()) + rb"(?![A-Za-z0-9_%.-])")


def vault_files(vault: Path) -> Iterable[Path]:
    for path in sorted(vault.rglob("*"), key=lambda p: p.as_posix()):
        if path.is_symlink() or not path.is_file():
            continue
        if path.name in SKIP_FILES:
            continue
        relative_parts = path.relative_to(vault).parts
        if any(part in SKIP_PARTS for part in relative_parts):
            continue
        yield path


def consumers(vault: Path, replacements: list[dict[str, str]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    found: list[dict[str, Any]] = []
    blocked_instructions: list[dict[str, Any]] = []
    blocked_binary: list[dict[str, Any]] = []
    for path in (vault_files(vault) if replacements else []):
        try:
            raw = path.read_bytes()
        except OSError:
            continue
        matches = []
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            content = None
        for replacement in replacements:
            count = len(bounded_bytes_pattern(replacement["from"]).findall(raw))
            if count:
                matches.append({**replacement, "count": count})
        if matches:
            item = {"path": rel(path, vault), "sha256": file_digest(path), "replacements": matches}
            if path.name in INSTRUCTION_NAMES:
                blocked_instructions.append(item)
                continue
            if content is None or "Artifacts" in path.relative_to(vault).parts or path.suffix.lower() in {".html", ".htm"} or "Hub Family" in path.relative_to(vault).parts:
                # Outputs and receipts are preserved bytes, even when UTF-8.
                # A referenced artifact needs review rather than silent rewrite.
                # This package does not install or refresh a custom HTML workspace.
                if "Artifacts" in path.relative_to(vault).parts:
                    item["reason"] = "preserved artifact references a path that will move"
                blocked_binary.append(item)
                continue
            found.append(item)
    return found, blocked_instructions, blocked_binary


def symlink_inventory(vault: Path) -> list[str]:
    blocked: list[str] = []
    for root_name in ("2. Projects", "3. Areas", "5. Resources", "Personal"):
        root = vault / root_name
        if root.is_symlink():
            blocked.append(rel(root, vault))
            continue
        if root.is_dir():
            blocked.extend(rel(path, vault) for path in root.rglob("*") if path.is_symlink())
    return sorted(set(blocked))


def core_plan(plan: dict[str, Any]) -> dict[str, Any]:
    return {key: plan[key] for key in ("schema_version", "moves", "mkdirs", "consumers", "blocked_instruction_consumers", "blocked_binary_consumers", "blocked_symlinks", "unknown_legacy_roots")}


def approval_token(plan: dict[str, Any]) -> str:
    encoded = json.dumps(core_plan(plan), sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def build_plan(vault: Path, profile: dict[str, Any]) -> dict[str, Any]:
    legacy_projects, unknown = legacy_personal_projects(vault, profile)
    moves: list[dict[str, Any]] = []
    replacements: list[dict[str, str]] = []
    future_projects: list[Path] = []

    target_goals = vault / profile["personal"]["goals_root"]
    legacy_goal_roots = [vault / item for item in profile["personal"]["legacy_goals_roots"]]
    existing_goal_roots = [path for path in legacy_goal_roots if path.is_dir()]
    for legacy_goals in existing_goal_roots:
        if len(existing_goal_roots) > 1:
            status = "blocked_multiple_sources"
        else:
            status = "blocked_collision" if target_goals.exists() else "ready"
        moves.append({"kind": "personal_goals", "source": rel(legacy_goals, vault), "target": rel(target_goals, vault), "status": status, "source_sha256": source_digest(legacy_goals)})
        if status == "ready":
            add_replacements(replacements, rel(legacy_goals, vault), rel(target_goals, vault))

    legacy_hub = vault / profile["personal"]["legacy_area_hub"]
    target_hub = vault / profile["personal"]["area_hub"]
    if legacy_hub.is_file() and frontmatter_type(legacy_hub) == "area-dashboard":
        status = "blocked_collision" if target_hub.exists() else "ready"
        moves.append({"kind": "personal_area_hub", "source": rel(legacy_hub, vault), "target": rel(target_hub, vault), "status": status, "source_sha256": source_digest(legacy_hub)})
        if status == "ready":
            add_replacements(replacements, rel(legacy_hub, vault), rel(target_hub, vault), include_stem=True)

    target_projects_root = vault / profile["personal"]["projects_root"]
    for source in legacy_projects:
        target = target_projects_root / source.name
        status = "blocked_collision" if target.exists() else "ready"
        moves.append({"kind": "personal_project", "source": rel(source, vault), "target": rel(target, vault), "status": status, "source_sha256": source_digest(source)})
        if status == "ready":
            add_replacements(replacements, rel(source, vault), rel(target, vault))
            future_projects.append(target)

    editable_consumers, blocked_instructions, blocked_binary = consumers(vault, replacements)
    plan: dict[str, Any] = {
        "schema_version": 1,
        "vault": str(vault.resolve()),
        "moves": moves,
        "mkdirs": mkdir_candidates(vault, profile, future_projects),
        "consumers": editable_consumers,
        "blocked_instruction_consumers": blocked_instructions,
        "blocked_binary_consumers": blocked_binary,
        "blocked_symlinks": symlink_inventory(vault),
        "unknown_legacy_roots": [rel(path, vault) for path in unknown],
    }
    plan["approval_token"] = approval_token(plan)
    return plan


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temp = Path(handle.name)
    temp.replace(path)


def create_parents(path: Path, vault: Path) -> list[str]:
    missing: list[Path] = []
    current = path
    while current != vault and not current.exists():
        missing.append(current)
        current = current.parent
    path.mkdir(parents=True, exist_ok=True)
    return [rel(item, vault) for item in reversed(missing)]


def validate_plan(vault: Path, plan: dict[str, Any], token: str) -> None:
    if plan.get("schema_version") != 1:
        raise StructureError("unsupported plan schema")
    if Path(plan.get("vault", "")).resolve() != vault.resolve():
        raise StructureError("plan was generated for a different vault")
    expected = approval_token(plan)
    if token != expected or plan.get("approval_token") != expected:
        raise StructureError("approval token does not match the exact plan")
    blocked = [move for move in plan["moves"] if move["status"] != "ready"]
    if blocked:
        raise StructureError("plan contains destination collisions; resolve them and generate a new preview")
    if plan.get("blocked_instruction_consumers"):
        raise StructureError("plan contains AGENTS.md or CLAUDE.md path consumers; human review must resolve them before apply")
    if plan.get("blocked_binary_consumers"):
        raise StructureError("plan contains non-text path consumers; review or remove them before apply")
    if plan.get("blocked_symlinks"):
        raise StructureError("plan contains symlinks in managed roots; resolve them before apply")
    for relative in plan["mkdirs"]:
        safe_path(vault, relative)
    allowed_replacements: list[dict[str, str]] = []
    for move in plan["moves"]:
        if move["status"] == "ready":
            add_replacements(
                allowed_replacements,
                move["source"],
                move["target"],
                include_stem=move["kind"] == "personal_area_hub",
            )
    for move in plan["moves"]:
        source, target = safe_path(vault, move["source"]), safe_path(vault, move["target"])
        if not source.exists() or source_digest(source) != move["source_sha256"]:
            raise StructureError(f"source changed after preview: {move['source']}")
        if target.exists():
            raise StructureError(f"destination appeared after preview: {move['target']}")
    for item in plan["consumers"]:
        path = safe_path(vault, item["path"])
        if not path.is_file() or file_digest(path) != item["sha256"]:
            raise StructureError(f"consumer changed after preview: {item['path']}")
        for replacement in item["replacements"]:
            if {"from": replacement["from"], "to": replacement["to"]} not in allowed_replacements:
                raise StructureError(f"consumer replacement does not match a planned move: {item['path']}")


def rewrite_consumers(vault: Path, plan: dict[str, Any], backup_root: Path, rewritten: list[dict[str, str]]) -> None:
    move_map = [(item["source"], item["target"]) for item in plan["moves"]]
    for item in plan["consumers"]:
        original_rel = item["path"]
        current_rel = original_rel
        for source, target in move_map:
            if current_rel == source or current_rel.startswith(source + "/"):
                current_rel = target + current_rel[len(source):]
        current = safe_path(vault, current_rel)
        backup = safe_path(backup_root, original_rel)
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(current, backup)
        content = current.read_bytes()
        for replacement in item["replacements"]:
            content = bounded_bytes_pattern(replacement["from"]).sub(replacement["to"].encode(), content)
        post_sha256 = hashlib.sha256(content).hexdigest()
        with tempfile.NamedTemporaryFile("wb", dir=current.parent, delete=False) as handle:
            handle.write(content)
            temp = Path(handle.name)
        shutil.copystat(current, temp)
        temp.replace(current)
        rewritten.append({"original_path": original_rel, "current_path": current_rel, "original_sha256": item["sha256"], "post_sha256": post_sha256})
        fail_after = int(os.environ.get("VAULT_STRUCTURE_TEST_FAIL_AFTER_CONSUMERS", "0"))
        if fail_after and len(rewritten) >= fail_after:
            raise StructureError("injected consumer rewrite failure")


def apply_plan(vault: Path, plan_path: Path, token: str) -> Path:
    with plan_path.open(encoding="utf-8") as handle:
        plan = json.load(handle)
    validate_plan(vault, plan, token)
    state_root = safe_path(vault, ".vault-structure-migrations")
    receipt_path = safe_path(vault, f".vault-structure-migrations/{token}.json")
    backup_root = safe_path(vault, f".vault-structure-backups/{token}")
    if receipt_path.exists():
        raise StructureError("this exact plan was already applied")
    backup_root.mkdir(parents=True, exist_ok=False)
    created: list[str] = []
    moved: list[dict[str, str]] = []
    rewritten: list[dict[str, str]] = []
    try:
        for move in plan["moves"]:
            source, target = safe_path(vault, move["source"]), safe_path(vault, move["target"])
            created.extend(create_parents(target.parent, vault))
            shutil.move(str(source), str(target))
            moved.append({"source": move["source"], "target": move["target"]})
        for relative in plan["mkdirs"]:
            path = safe_path(vault, relative)
            if not path.exists():
                path.mkdir(parents=True)
                created.append(relative)
        rewrite_consumers(vault, plan, backup_root, rewritten)
        receipt = {
            "schema_version": 1,
            "vault": str(vault.resolve()),
            "approval_token": token,
            "moves": moved,
            "created_directories": created,
            "rewritten_consumers": rewritten,
            "backup_root": rel(backup_root, vault),
        }
        atomic_json(receipt_path, receipt)
        return receipt_path
    except Exception:
        recovery_ok = True
        for item in reversed(rewritten):
            try:
                backup = safe_path(backup_root, item["original_path"])
                current = safe_path(vault, item["current_path"])
                shutil.copy2(backup, current)
            except Exception:
                recovery_ok = False
        for item in reversed(moved):
            source, target = safe_path(vault, item["source"]), safe_path(vault, item["target"])
            if target.exists() and not source.exists():
                source.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(target), str(source))
        for relative in sorted(set(created), key=lambda value: (value.count("/"), value), reverse=True):
            try:
                safe_path(vault, relative).rmdir()
            except OSError:
                pass
        if recovery_ok:
            shutil.rmtree(backup_root, ignore_errors=True)
        raise


def rollback(vault: Path, receipt_path: Path) -> None:
    receipts_root = safe_path(vault, ".vault-structure-migrations").resolve()
    resolved_receipt = receipt_path.resolve()
    if receipt_path.is_symlink() or resolved_receipt.parent != receipts_root:
        raise StructureError("receipt must be an ordinary file in this vault's migration receipt directory")
    with resolved_receipt.open(encoding="utf-8") as handle:
        receipt = json.load(handle)
    if Path(receipt.get("vault", "")).resolve() != vault.resolve():
        raise StructureError("receipt belongs to a different vault")
    backup_root = safe_path(vault, receipt["backup_root"])
    for item in receipt["rewritten_consumers"]:
        current = safe_path(vault, item["current_path"])
        if not current.is_file() or file_digest(current) != item["post_sha256"]:
            raise StructureError(f"cannot rollback changed consumer: {item['current_path']}")
        backup = safe_path(backup_root, item["original_path"])
        if not backup.is_file() or file_digest(backup) != item["original_sha256"]:
            raise StructureError(f"cannot rollback missing or changed backup: {item['original_path']}")
    for item in reversed(receipt["moves"]):
        source, target = safe_path(vault, item["source"]), safe_path(vault, item["target"])
        if source.exists() or not target.exists():
            raise StructureError(f"cannot rollback move safely: {item['target']}")
    for item in reversed(receipt["moves"]):
        source, target = safe_path(vault, item["source"]), safe_path(vault, item["target"])
        source.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(target), str(source))
    for item in receipt["rewritten_consumers"]:
        backup = safe_path(backup_root, item["original_path"])
        destination = safe_path(vault, item["original_path"])
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(backup, destination)
    reverse_moves = [(item["target"], item["source"]) for item in receipt["moves"]]
    restored_created: list[str] = []
    for relative in receipt["created_directories"]:
        restored = relative
        for target, source in reverse_moves:
            if restored == target or restored.startswith(target + "/"):
                restored = source + restored[len(target):]
        restored_created.append(restored)
    for relative in sorted(set(restored_created), key=lambda value: (value.count("/"), value), reverse=True):
        path = safe_path(vault, relative)
        try:
            path.rmdir()
        except OSError:
            pass
    resolved_receipt.unlink()
    shutil.rmtree(backup_root)
    for parent in (backup_root.parent, resolved_receipt.parent):
        try:
            parent.rmdir()
        except OSError:
            pass


def scaffold(vault: Path, profile: dict[str, Any]) -> list[str]:
    blocked = symlink_inventory(vault)
    if blocked:
        raise StructureError("managed roots contain symlinks: " + ", ".join(blocked))
    created = mkdir_candidates(vault, profile)
    for relative in created:
        safe_path(vault, relative).mkdir(parents=True, exist_ok=True)
    return created


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    for name in ("scaffold", "plan"):
        command = sub.add_parser(name)
        command.add_argument("--vault", required=True, type=Path)
        if name == "plan":
            command.add_argument("--output", required=True, type=Path)
    apply_cmd = sub.add_parser("apply")
    apply_cmd.add_argument("--vault", required=True, type=Path)
    apply_cmd.add_argument("--plan", required=True, type=Path)
    apply_cmd.add_argument("--approval-token", required=True)
    rollback_cmd = sub.add_parser("rollback")
    rollback_cmd.add_argument("--vault", required=True, type=Path)
    rollback_cmd.add_argument("--receipt", required=True, type=Path)
    return result


def main() -> int:
    args = parser().parse_args()
    sys.dont_write_bytecode = True  # A refused path/consent check must not create a cache file.
    from license_consent import ensure_acceptance, safe_workspace
    # Inspect the supplied path before canonicalizing it; resolving first would
    # erase evidence of a redirected workspace. Rollback shares path safety.
    vault = safe_workspace(args.vault)
    if not vault.is_dir():
        raise StructureError(f"vault does not exist: {vault}")
    # Rollback remains available to undo an earlier migration without new assent.
    # All installation/update writes require a matching existing human response.
    if args.command != "rollback":
        ensure_acceptance(vault, check_only=True)
    profile = load_profile()
    if args.command == "scaffold":
        created = scaffold(vault, profile)
        print(json.dumps({"created": created, "created_count": len(created)}, indent=2))
    elif args.command == "plan":
        plan = build_plan(vault, profile)
        atomic_json(args.output, plan)
        print(json.dumps({"plan": str(args.output), "approval_token": plan["approval_token"], "moves": len(plan["moves"]), "mkdirs": len(plan["mkdirs"]), "consumers": len(plan["consumers"]), "blocked_instruction_consumers": len(plan["blocked_instruction_consumers"]), "blocked_binary_consumers": len(plan["blocked_binary_consumers"]), "blocked_symlinks": plan["blocked_symlinks"], "unknown_legacy_roots": plan["unknown_legacy_roots"]}, indent=2))
    elif args.command == "apply":
        receipt = apply_plan(vault, args.plan, args.approval_token)
        print(json.dumps({"applied": True, "receipt": str(receipt)}, indent=2))
    else:
        rollback(vault, args.receipt)
        print(json.dumps({"rolled_back": True}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (StructureError, OSError, json.JSONDecodeError, KeyError, TypeError, ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
