"""Differential model of SceneDelegate's last-reply traversal (not an iOS test).

Run: python -m unittest discover -s test -p reply_boundary_search_test.py
The model verifies ordering and node visits; it does not measure VoiceOver latency.
"""
import random
import unittest


class Node:
    def __init__(self, group=None, readable=True, children=()):
        self.group = group
        self.readable = readable
        self.children = list(children)


def collect(node, group, visits):
    visits[0] += 1
    result = [node] if node.group == group and node.readable else []
    for child in node.children:
        result.extend(collect(child, group, visits))
    return result


def last(node, group, visits):
    visits[0] += 1
    for child in reversed(node.children):
        match = last(child, group, visits)
        if match is not None:
            return match
    return node if node.group == group and node.readable else None


class BoundarySearchTests(unittest.TestCase):
    def check_tree(self, root, group):
        expected = collect(root, group, [0])
        self.assertIs(last(root, group, [0]), expected[-1] if expected else None)

    def test_nested_reply_descendant_precedes_parent_in_reverse_search(self):
        child = Node('reply')
        root = Node('reply', children=[child])
        self.assertIs(last(root, 'reply', [0]), child)

    def test_footer_and_other_thread_do_not_become_last_reply(self):
        reply = Node('reply')
        root = Node(children=[reply, Node('other'), Node('reply', readable=False), Node()])
        self.assertIs(last(root, 'reply', [0]), reply)
        self.assertIsNone(last(root, 'missing', [0]))

    def test_append_remove_and_replace_without_cached_nodes(self):
        root = Node(children=[Node('reply')])
        for _ in range(30):
            root.children.append(Node('reply'))
            self.check_tree(root, 'reply')
        for _ in range(30):
            root.children.pop()
            self.check_tree(root, 'reply')
        root.children = [Node('other'), Node('reply')]
        self.check_tree(root, 'reply')
        self.check_tree(Node(), 'reply')

    def test_differential_random_trees(self):
        rng = random.Random(5666)
        for _ in range(300):
            root = Node()
            nodes = [root]
            for _ in range(rng.randrange(1, 200)):
                node = Node(rng.choice([None, 'reply', 'other']), rng.choice([True, False]))
                rng.choice(nodes).children.append(node)
                nodes.append(node)
            for group in ['reply', 'other', 'missing']:
                self.check_tree(root, group)

    def test_flat_500_reply_model_skips_preceding_replies(self):
        root = Node(children=[Node('reply') for _ in range(500)] + [Node()])
        old_visits, new_visits = [0], [0]
        expected = collect(root, 'reply', old_visits)[-1]
        self.assertIs(last(root, 'reply', new_visits), expected)
        self.assertEqual(old_visits[0], 502)
        self.assertEqual(new_visits[0], 3)


if __name__ == '__main__':
    unittest.main()
